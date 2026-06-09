//
//  DeepSeekLanguageModel+Executor.swift
//  FoundationDeepSeek
//
//  Created by Arkivili Collindort on 09/06/2026
//

import Foundation
import FoundationModels
import OpenAI

public struct DeepSeekLanguageModelExecutor: LanguageModelExecutor {
    public typealias Model = DeepSeekLanguageModel

    public struct Configuration: Hashable, Sendable {
        public enum DeepSeekModel: String, Sendable {
            case flash = "deepseek-v4-flash"
            case pro = "deepseek-v4-pro"
        }
        
        public var apiKey: String
        public var baseURL: URL
        public var modelID: DeepSeekModel

        public init(
            apiKey: String,
            baseURL: URL = URL(string: "https://api.deepseek.com")!,
            modelID: DeepSeekModel = .flash
        ) {
            self.apiKey = apiKey
            self.baseURL = baseURL
            self.modelID = modelID
        }
    }

    public enum DeepSeekError: LocalizedError {
        case invalidResponse
        case requestFailed(statusCode: Int, body: String)
        case emptyAPIKey

        public var errorDescription: String? {
            switch self {
            case .invalidResponse:
                "DeepSeek returned an invalid response."
            case .requestFailed(let statusCode, let body):
                "DeepSeek request failed with status \(statusCode): \(body)"
            case .emptyAPIKey:
                "DeepSeek API key is empty."
            }
        }
    }

    private let configuration: Configuration
    private let decoder = JSONDecoder()

    public init(configuration: Configuration) throws {
        guard
            !configuration.apiKey.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
        else {
            throw DeepSeekError.emptyAPIKey
        }

        self.configuration = configuration
    }

    public func prewarm(model: Model, transcript: Transcript) {
        // Remote API model: nothing to preload locally.
    }

    public func respond(
        to request: LanguageModelExecutorGenerationRequest,
        model: DeepSeekLanguageModel,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        // configurations
        let openAI = OpenAI(
            configuration: .init(
                token: configuration.apiKey,
                host: configuration.baseURL.host() ?? "",
                basePath: configuration.baseURL.path()
            )
        )
        
        let query = try await makeQuery(to: request, model: model)
        
        var toolCallStates: [Int: StreamingToolCallState] = [:]
        
        for await response in openAI.chatsStream(query: query) {
            for choice in response.choices {
                if let content = choice.delta.content {
                    await channel.send(
                        .response(action: .appendText(content, tokenCount: 1))
                    )
                }
                if let reasoning = choice.delta.reasoning {
                    await channel.send(
                        .reasoning(action: .appendText(reasoning, tokenCount: 1))
                    )
                }
                if let toolCalls = choice.delta.toolCalls {
                    for toolCall in toolCalls {
                        let index = toolCall.index
                        
                        var state = toolCallStates[index] ?? StreamingToolCallState()
                        
                        if let id = toolCall.id {
                            state.id = id
                        }
                        
                        if let name = toolCall.function?.name {
                            state.name = name
                        }
                        
                        if let arguments = toolCall.function?.arguments {
                            state.pendingArguments += arguments
                        }
                        
                        if let id = state.id,
                           let name = state.name,
                           !state.pendingArguments.isEmpty {
                            await channel.send(
                                .toolCalls(
                                    action: .toolCall(
                                        id: id,
                                        name: name,
                                        action: .appendArguments(
                                            state.pendingArguments,
                                            tokenCount: max(1, state.pendingArguments.count / 4)
                                        )
                                    )
                                )
                            )
                            
                            state.pendingArguments.removeAll(keepingCapacity: true)
                        }
                        
                        toolCallStates[index] = state
                    }
                }
            }
            
            if let usage = response.usage {
                if let completionDetail = usage.completionTokensDetails,
                   let promptDetail = usage.promptTokensDetails {
                    await channel.send(
                        .response(
                            action: .updateUsage(
                                input: .init(totalTokenCount: usage.promptTokens, cachedTokenCount: promptDetail.cachedTokens),
                                output: .init(totalTokenCount: usage.completionTokens, reasoningTokenCount: completionDetail.reasoningTokens ?? 0)
                            )
                        )
                    )
                }
            }
        }
    }
    
    func makeQuery(
        to request: LanguageModelExecutorGenerationRequest,
        model: DeepSeekLanguageModel
    ) async throws -> ChatQuery {
        // message transformation
        let messages: [ChatQuery.ChatCompletionMessageParam] = try await messageTransformer(request.transcript)
        
        // tools
        let tools: [ChatQuery.ChatCompletionToolParam] = try request.enabledToolDefinitions.compactMap { definition in
            let jsonEncoder = JSONEncoder()
            let _schema = try jsonEncoder.encode(definition.parameters)
            let jsonDecoder = JSONDecoder()
            let schema = try jsonDecoder.decode(JSONSchema.self, from: _schema)
            return ChatQuery.ChatCompletionToolParam(
                function: ChatQuery.ChatCompletionToolParam.FunctionDefinition(
                    name: definition.name,
                    description: definition.description,
                    parameters: schema,
                    strict: true
                )
            )
        }
        
        var metadata = try request.metadata.mapValues { value in
            let encoder = JSONEncoder()
            let data = try encoder.encode(value)
            return String(data: data, encoding: .utf8)!
        }
        metadata["id"] = request.id.uuidString
        
        return ChatQuery(
            messages: messages,
            model: configuration.modelID.rawValue,
            reasoningEffort: {
                if let level = request.contextOptions.reasoningLevel {
                    switch level {
                    case .light: return .low
                    case .moderate: return .medium
                    case .deep: return .high
                    default:
                        return nil
                    }
                } else {
                    return nil
                }
            }(),
            maxCompletionTokens: request.generationOptions.maximumResponseTokens,
            metadata: metadata,
            responseFormat: {
                if let schema = request.schema {
                    return .jsonSchema(ChatQuery.StructuredOutputConfigurationOptions(name: "schema", schema: .dynamicJsonSchema(schema)))
                } else {
                    return nil
                }
            }(),
            temperature: request.generationOptions.temperature,
            toolChoice: {
                switch request.generationOptions.toolCallingMode {
                case .some(let mode): switch mode {
                case .allowed: .auto
                case .required: .required
                case .disallowed: ChatQuery.ChatCompletionFunctionCallOptionParam.none
                default: nil
                }
                case .none: nil
                }
            }(),
            tools: tools,
            stream: true,
            streamOptions: .init(includeUsage: true)
        )
    }
    
    func messageTransformer(_ transcript: Transcript) async throws -> [ChatQuery.ChatCompletionMessageParam] {
        try await withThrowingTaskGroup { group in
            for (id, entry) in transcript.enumerated() {
                group.addTask {
                    try Task.checkCancellation()
                    return (id, try entryTransformer(entry))
                }
            }
            
            var results = [(Int, ChatQuery.ChatCompletionMessageParam?)]()
            results.reserveCapacity(transcript.count)
            
            for try await result in group {
                results.append(result)
            }
            
            return results.sorted {
                $0.0 < $1.0
            }.compactMap(\.1)
        }
    }
    
    func entryTransformer(_ entry: Transcript.Entry) throws -> ChatQuery.ChatCompletionMessageParam? {
        switch entry {
        case .instructions(let instructions):
            return .system(
                ChatQuery.ChatCompletionMessageParam.SystemMessageParam(
                    content: .contentParts(
                        instructions.segments.compactMap { segment in
                            switch segment {
                            case .text(let text):
                                ChatQuery.ChatCompletionMessageParam.ContentPartTextParam(text: text.content)
                            case .structure(let structure):
                                ChatQuery.ChatCompletionMessageParam.ContentPartTextParam(
                                    text: #"{"content":"\#(structure.content.jsonString)","schemaName":"\#(structure.schemaName)"}"#
                                )
                            default:
                                nil
                            }
                        }
                    )
                )
            )
        case .prompt(let prompt):
            return .user(
                ChatQuery.ChatCompletionMessageParam.UserMessageParam(
                    content: ChatQuery.ChatCompletionMessageParam.UserMessageParam.Content.contentParts(
                        try prompt.segments.compactMap { segment in
                            switch segment {
                            case .text(let textSegment):
                                return .text(
                                    ChatQuery.ChatCompletionMessageParam.ContentPartTextParam(text: textSegment.content)
                                )
                            case .structure(let structuredSegment):
                                let content = structuredSegment.content.jsonString
                                let schemaName = structuredSegment.schemaName
                                return .text(
                                    ChatQuery.ChatCompletionMessageParam.ContentPartTextParam(
                                        text: #"{"content":"\#(content)","schemaName":"\#(schemaName)"}"#
                                    )
                                )
                            case .attachment(let attachmentSegment):
                                switch attachmentSegment.content {
                                case .image(let image):
                                    if let url = image.url {
                                        return .image(
                                            ChatQuery.ChatCompletionMessageParam.ContentPartImageParam(
                                                imageUrl: ChatQuery.ChatCompletionMessageParam.ContentPartImageParam.ImageURL(
                                                    url: url.absoluteString, detail: nil
                                                )
                                            )
                                        )
                                    } else {
                                        guard let imageData = FDSCGImageToPNGData(image.cgImage) else {
                                            return nil
                                        }
                                        return .image(
                                            ChatQuery.ChatCompletionMessageParam.ContentPartImageParam(
                                                imageUrl: ChatQuery.ChatCompletionMessageParam.ContentPartImageParam.ImageURL(
                                                    imageData: imageData, detail: nil
                                                )
                                            )
                                        )
                                    }
                                @unknown default:
                                    return nil
                                }
                            case .custom(let customSegment):
                                let jsonEncoder = JSONEncoder()
                                let data = try jsonEncoder.encode(customSegment.content)
                                guard let jsonString = String(data: data, encoding: .utf8) else {
                                    return nil
                                }
                                return .text(
                                    ChatQuery.ChatCompletionMessageParam.ContentPartTextParam(
                                        text: jsonString
                                    )
                                )
                            @unknown default:
                                return nil
                            }
                        }
                    )
                )
            )
        case .toolOutput(let toolOutput):
            return .tool(
                ChatQuery.ChatCompletionMessageParam.ToolMessageParam(
                    content: .contentParts(
                        toolOutput.segments.compactMap { segment in
                            switch segment {
                            case .text(let text):
                                ChatQuery.ChatCompletionMessageParam.ContentPartTextParam(text: text.content)
                            case .structure(let structure):
                                ChatQuery.ChatCompletionMessageParam.ContentPartTextParam(
                                    text: #"{"content":"\#(structure.content.jsonString)","schemaName":"\#(structure.schemaName)"}"#
                                )
                            default:
                                nil
                            }
                        }
                    ),
                    toolCallId: toolOutput.id
                )
            )
        case .response(let response):
            return .assistant(
                ChatQuery.ChatCompletionMessageParam.AssistantMessageParam(
                    content: .contentParts(
                        response.segments.compactMap { segment in
                            switch segment {
                            case .text(let text):
                                return .text(
                                    ChatQuery.ChatCompletionMessageParam.ContentPartTextParam(text: text.content)
                                )
                            case .structure(let structure):
                                return .text(
                                    ChatQuery.ChatCompletionMessageParam.ContentPartTextParam(
                                        text: #"{"content":"\#(structure.content.jsonString)","schemaName":"\#(structure.schemaName)"}"#
                                    )
                                )
                            default:
                                return nil
                            }
                        }
                    )
                )
            )
        case .toolCalls(let toolCalls):
            return .assistant(
                ChatQuery.ChatCompletionMessageParam.AssistantMessageParam(
                    toolCalls: toolCalls.compactMap { toolCall in
                        return ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam(
                            id: toolCall.id,
                            function: ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam.FunctionCall(
                                arguments: toolCall.arguments.jsonString,
                                name: toolCall.toolName
                            )
                        )
                    }
                )
            )
        case .reasoning(_):
            return nil // FIXME: Need justify
        @unknown default:
            return nil
        }
    }
    
    private struct StreamingToolCallState {
        var id: String?
        var name: String?
        var pendingArguments = ""
        
        var isReady: Bool {
            id != nil && name != nil
        }
    }
}
