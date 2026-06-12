//
//  OpenAIExecutor+Completion.swift
//  foundation-openai
//
//  Created by Arkivili Collindort on 11/06/2026
//

import Foundation
import FoundationModels
import OpenAI

extension OpenAILanguageModelExecutor {
    func _chatCompletion(
        to request: LanguageModelExecutorGenerationRequest,
        model: Model,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        // configurations
        let openAI = makeOpenAIClient(model: model)
        
        let query = try await makeQuery(to: request, model: model, transformer: configuration.transformer)
        
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
        model: Model,
        transformer: AnyQueryTransformer
    ) async throws -> ChatQuery {
        // message transformation
        var messages: [ChatQuery.ChatCompletionMessageParam] = try await messageTransformer(request.transcript, transformer: transformer)
        
        if let outputSchema = request.schema {
            // inject a .system message at the front of the message
            // that guide models output.
            
            let schemaVariant: _SchemaVariant = if request.contextOptions.includeSchemaInPrompt == true {
                try {
                    let _jsonSchema = try encoder.encode(outputSchema)
                    let jsonSchema = String(data: _jsonSchema, encoding: .utf8)!
                    return .containSchemaInPrompt(schema: jsonSchema)
                }()
            } else {
                .regular
            }
            messages.insert(
                .system(
                    .init(
                        content: .textContent(
                            makeOutputSchemaPrompt(with: schemaVariant)
                        )
                    )
                ),
                at: 0
            )
        }
        
        // tools
        let tools: [ChatQuery.ChatCompletionToolParam] = try request.enabledToolDefinitions.compactMap { definition in
            let jsonEncoder = JSONEncoder()
            let _schema = try jsonEncoder.encode(definition.parameters)
            let jsonDecoder = JSONDecoder()
            let schema = try jsonDecoder.decode(JSONSchema.self, from: _schema)
            
            let isStrict = switch configuration.toolCallingGenerationStrictness {
            case .tolerant: false
            case .strict: true
            }
            
            return ChatQuery.ChatCompletionToolParam(
                function: ChatQuery.ChatCompletionToolParam.FunctionDefinition(
                    name: definition.name,
                    description: definition.description,
                    parameters: schema,
                    strict: isStrict
                )
            )
        }
        
        var metadata = try request.metadata.mapValues { value in
            let encoder = JSONEncoder()
            let data = try encoder.encode(value)
            return String(data: data, encoding: .utf8)!
        }
        metadata["id"] = request.id.uuidString
        
        let modelID = model.model.rawValue
        
        return ChatQuery(
            messages: messages,
            model: modelID,
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
    
    func messageTransformer(
        _ transcript: Transcript,
        transformer: AnyQueryTransformer
    ) async throws -> [ChatQuery.ChatCompletionMessageParam] {
        try await withThrowingTaskGroup { group in
            for (id, entry) in transcript.enumerated() {
                group.addTask {
                    try Task.checkCancellation()
                    return (id, try Self.entryTransformer(entry, transformer: transformer))
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
    
    static func entryTransformer(
        _ entry: Transcript.Entry,
        transformer: AnyQueryTransformer
    ) throws -> ChatQuery.ChatCompletionMessageParam? {
        switch entry {
        case .instructions(let instructions):
            return try transformer.transformInstructions(from: instructions)
        case .prompt(let prompt):
            return try transformer.transformPrompt(from: prompt)
        case .toolOutput(let toolOutput):
            return try transformer.transformToolOutput(from: toolOutput)
        case .response(let response):
            return try transformer.transformResponse(from: response)
        case .toolCalls(let toolCalls):
            return try transformer.transformToolCalls(from: toolCalls)
        case .reasoning(let reasoning):
            return try transformer.transformReasoning(from: reasoning)
        @unknown default:
            return nil
        }
    }
    
    private struct StreamingToolCallState {
        var id: String?
        var name: String?
        var pendingArguments = ""
    }
}
