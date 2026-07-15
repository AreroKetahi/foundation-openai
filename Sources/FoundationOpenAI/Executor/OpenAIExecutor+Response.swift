//
//  OpenAIExecutor+Response.swift
//  foundation-openai
//
//  Created by Arkivili Collindort on 11/06/2026
//

import Foundation
import FoundationModels
import OpenAI

@available(anyAppleOS 27.0, *)
extension OpenAILanguageModelExecutor {
    func _response(
        to request: LanguageModelExecutorGenerationRequest,
        model: Model,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        let openAI = makeOpenAIClient(model: model)
        let query = try await makeResponseQuery(to: request, model: model, transformer: configuration.transformer)
        var toolCallStates: [Int: ResponseStreamingToolCallState] = [:]
        
        for try await event in openAI.responses.createResponseStreaming(query: query) {
            switch event {
            case .outputText(.delta(let delta)):
                await channel.send(
                    .response(action: .appendText(delta.delta, tokenCount: 1))
                )
                
            case .reasoning(.delta(let delta)):
                await channel.send(
                    .reasoning(action: .appendText(delta.delta, tokenCount: 1))
                )
                
            case .reasoningSummaryText(.delta(let delta)):
                await channel.send(
                    .reasoning(action: .appendText(delta.delta, tokenCount: 1))
                )
                
            case .outputItem(.added(let added)):
                if case .functionToolCall(let toolCall) = added.item {
                    var state = toolCallStates[added.outputIndex] ?? ResponseStreamingToolCallState()
                    state.id = toolCall.callId
                    state.name = toolCall.name
                    toolCallStates[added.outputIndex] = state
                }
                
            case .outputItem(.done(let done)):
                switch done.item {
                case .functionToolCall(let toolCall):
                    var state = toolCallStates[done.outputIndex] ?? ResponseStreamingToolCallState()
                    state.id = toolCall.callId
                    state.name = toolCall.name
                    if await flushResponseToolCallIfPossible(state, channel: channel) {
                        state.hasFlushed = true
                        state.pendingArguments.removeAll(keepingCapacity: true)
                    }
                    toolCallStates[done.outputIndex] = state
                case .reasoning(let reasoning):
                    await sendReasoningSignatureIfPresent(reasoning, channel: channel)
                default:
                    break
                }
                
            case .functionCallArguments(.delta(let delta)):
                var state = toolCallStates[delta.outputIndex] ?? ResponseStreamingToolCallState()
                if state.id == nil {
                    state.id = delta.itemId
                }
                state.pendingArguments += delta.delta
                toolCallStates[delta.outputIndex] = state
                
            case .functionCallArguments(.done(let done)):
                var state = toolCallStates[done.outputIndex] ?? ResponseStreamingToolCallState()
                if state.id == nil {
                    state.id = done.itemId
                }
                if let name = done.name {
                    state.name = name
                }
                if state.pendingArguments.isEmpty {
                    state.pendingArguments = done.arguments
                }
                if await flushResponseToolCallIfPossible(state, channel: channel) {
                    state.hasFlushed = true
                    state.pendingArguments.removeAll(keepingCapacity: true)
                }
                toolCallStates[done.outputIndex] = state
                
            case .completed(let event):
                if let usage = event.response.usage {
                    await sendResponseUsage(usage, channel: channel)
                }
                
            case .failed(let event):
                throw OpenAIError.requestFailed(
                    statusCode: -1,
                    body: event.response.error?.message ?? "Responses API request failed."
                )
                
            case .error(let error):
                throw OpenAIError.requestFailed(statusCode: -1, body: error.message)
                
            default:
                break
            }
        }
    }
    
    func makeResponseQuery(
        to request: LanguageModelExecutorGenerationRequest,
        model: Model,
        transformer: AnyQueryTransformer
    ) async throws -> CreateModelResponseQuery {
        var inputItems = try await Self.responseInputItems(from: request.transcript, transformer: transformer)
        
        if let outputSchema = request.schema {
            let schemaVariant: _SchemaVariant = if request.contextOptions.includeSchemaInPrompt == true {
                try {
                    let _jsonSchema = try encoder.encode(outputSchema)
                    let jsonSchema = String(data: _jsonSchema, encoding: .utf8)!
                    return .containSchemaInPrompt(schema: jsonSchema)
                }()
            } else {
                .regular
            }
            inputItems.insert(
                .inputMessage(
                    EasyInputMessage(
                        role: .system,
                        content: .textInput(
                            makeOutputSchemaPrompt(with: schemaVariant)
                        )
                    )
                ),
                at: 0
            )
        }
        
        let tools: [OpenAI::Tool] = try request.enabledToolDefinitions.map { definition in
            let data = try encoder.encode(definition.parameters)
            let schema = try decoder.decode(JSONSchema.self, from: data)
            let isStrict = switch configuration.toolCallingGenerationStrictness {
            case .tolerant: false
            case .strict: true
            }
            
            return .functionTool(
                FunctionTool(
                    name: definition.name,
                    description: definition.description,
                    parameters: schema,
                    strict: isStrict
                )
            )
        }
        
        var metadata = try request.metadata.mapValues { value in
            let data = try encoder.encode(value)
            return String(data: data, encoding: .utf8) ?? ""
        }
        metadata["id"] = request.id.uuidString
        
        return CreateModelResponseQuery(
            input: .inputItemList(inputItems),
            model: model.model.rawValue,
            maxOutputTokens: request.generationOptions.maximumResponseTokens,
            metadata: .init(additionalProperties: metadata),
            parallelToolCalls: tools.isEmpty ? nil : true,
            reasoning: Self.responseReasoning(from: request.contextOptions.reasoningLevel),
            stream: true,
            temperature: request.generationOptions.temperature,
            text: Self.responseTextConfiguration(schema: request.schema),
            toolChoice: Self.responseToolChoice(from: request.generationOptions.toolCallingMode),
            tools: tools.isEmpty ? nil : tools
        )
    }
    
    private static func responseInputItems(
        from transcript: Transcript,
        transformer: AnyQueryTransformer
    ) async throws -> [InputItem] {
        try await withThrowingTaskGroup { group in
            for (index, entry) in transcript.enumerated() {
                group.addTask {
                    try Task.checkCancellation()
                    return (index, try Self.responseInputItems(from: entry, transformer: transformer))
                }
            }
            
            var results = [(Int, [InputItem])]()
            results.reserveCapacity(transcript.count)
            
            for try await result in group {
                results.append(result)
            }
            
            return results.sorted { $0.0 < $1.0 }.flatMap(\.1)
        }
    }
    
    private static func responseInputItems(
        from entry: Transcript.Entry,
        transformer: AnyQueryTransformer
    ) throws -> [InputItem] {
        switch entry {
        case .reasoning(let reasoning):
            return responseInputItems(from: reasoning)
        default:
            guard let message = try entryTransformer(entry, transformer: transformer) else {
                return []
            }
            return try responseInputItems(from: message)
        }
    }
    
    private static func responseInputItems(
        from reasoning: Transcript.Reasoning
    ) -> [InputItem] {
        let content = reasoningTextContent(from: reasoning.segments)
        let encryptedContent = encryptedReasoningContent(from: reasoning)
        
        guard encryptedContent != nil || content?.isEmpty == false else {
            return []
        }
        
        return [
            .item(
                .reasoningItem(
                    Components.Schemas.ReasoningItem(
                        _type: .reasoning,
                        id: reasoning.id,
                        encryptedContent: encryptedContent,
                        summary: [],
                        content: content,
                        status: .completed
                    )
                )
            )
        ]
    }
    
    private static func reasoningTextContent(
        from segments: [Transcript.Segment]
    ) -> [Components.Schemas.ReasoningTextContent]? {
        let text = segments.compactMap(reasoningText(from:)).joined(separator: "\n")
        guard !text.isEmpty else {
            return nil
        }
        
        return [
            Components.Schemas.ReasoningTextContent(
                _type: .reasoningText,
                text: text
            )
        ]
    }
    
    private static func reasoningText(from segment: Transcript.Segment) -> String? {
        switch segment {
        case .text(let text):
            return text.content
        case .structure(let structure):
            return #"{"content":"\#(structure.content.jsonString)","schemaName":"\#(structure.schemaName)"}"#
        case .custom(let custom):
            return custom.description
        default:
            return nil
        }
    }
    
    private static func encryptedReasoningContent(
        from reasoning: Transcript.Reasoning
    ) -> String? {
        if let metadataValue = reasoning.metadata["encrypted_content"] ?? reasoning.metadata["encryptedContent"],
           let encryptedContent = metadataValue as? String {
            return encryptedContent
        }
        
        guard let signature = reasoning.signature else {
            return nil
        }
        
        return String(data: signature, encoding: .utf8) ?? signature.base64EncodedString()
    }
    
    private static func responseInputItems(
        from message: ChatQuery.ChatCompletionMessageParam
    ) throws -> [InputItem] {
        switch message {
        case .system(let system):
            return [messageInput(role: .system, content: text(from: system.content))]
            
        case .developer(let developer):
            return [messageInput(role: .developer, content: text(from: developer.content))]
            
        case .user(let user):
            return [
                .inputMessage(
                    EasyInputMessage(
                        role: .user,
                        content: responseContent(from: user.content)
                    )
                )
            ]
            
        case .assistant(let assistant):
            var items: [InputItem] = []
            if let content = assistant.content,
               let text = text(from: content),
               !text.isEmpty {
                items.append(messageInput(role: .assistant, content: text))
            }
            
            if let toolCalls = assistant.toolCalls {
                items.append(
                    contentsOf: toolCalls.map { toolCall in
                        .item(
                            .functionToolCall(
                                Components.Schemas.FunctionToolCall(
                                    id: toolCall.id,
                                    _type: .functionCall,
                                    callId: toolCall.id,
                                    name: toolCall.function.name,
                                    arguments: toolCall.function.arguments,
                                    status: .completed
                                )
                            )
                        )
                    }
                )
            }
            
            return items
            
        case .tool(let tool):
            return [
                .item(
                    .functionCallOutputItemParam(
                        Components.Schemas.FunctionCallOutputItemParam(
                            callId: tool.toolCallId,
                            _type: .functionCallOutput,
                            output: .case1(text(from: tool.content) ?? ""),
                            status: .completed
                        )
                    )
                )
            ]
        }
    }
    
    private static func responseContent(
        from content: ChatQuery.ChatCompletionMessageParam.UserMessageParam.Content
    ) -> EasyInputMessage.ContentPayload {
        switch content {
        case .string(let text):
            return .textInput(text)
        case .contentParts(let parts):
            return .inputItemContentList(
                parts.compactMap { part in
                    switch part {
                    case .text(let text):
                        return .inputText(
                            Components.Schemas.InputTextContent(
                                _type: .inputText,
                                text: text.text
                            )
                        )
                    case .image(let image):
                        return .inputImage(
                            InputImage(
                                _type: .inputImage,
                                imageUrl: image.imageUrl.url,
                                detail: Self.responseImageDetail(from: image.imageUrl.detail)
                            )
                        )
                    default:
                        return nil
                    }
                }
            )
        }
    }
    
    private static func responseImageDetail(
        from detail: ChatQuery.ChatCompletionMessageParam.ContentPartImageParam.ImageURL.Detail?
    ) -> InputImage.DetailPayload {
        switch detail {
        case .high: .high
        case .low: .low
        case .auto, .none: .auto
        }
    }
    
    private static func messageInput(
        role: EasyInputMessage.RolePayload,
        content: String
    ) -> InputItem {
        .inputMessage(
            EasyInputMessage(
                role: role,
                content: .textInput(content)
            )
        )
    }
    
    private static func text(
        from content: ChatQuery.ChatCompletionMessageParam.TextContent
    ) -> String {
        switch content {
        case .textContent(let text):
            return text
        case .contentParts(let parts):
            return parts.map(\.text).joined(separator: "\n")
        }
    }
    
    private static func text(
        from content: ChatQuery.ChatCompletionMessageParam.TextOrRefusalContent
    ) -> String? {
        switch content {
        case .textContent(let text):
            return text
        case .contentParts(let parts):
            let text = parts.compactMap { part in
                if case .text(let text) = part {
                    return text.text
                }
                return nil
            }.joined(separator: "\n")
            return text.isEmpty ? nil : text
        }
    }
    
    private static func text(
        from content: ChatQuery.ChatCompletionMessageParam.TextContent
    ) -> String? {
        switch content {
        case .textContent(let text):
            return text
        case .contentParts(let parts):
            let text = parts.map(\.text).joined(separator: "\n")
            return text.isEmpty ? nil : text
        }
    }
    
    private static func responseReasoning<ReasoningLevel>(
        from level: ReasoningLevel?
    ) -> Components.Schemas.Reasoning? {
        guard let level else {
            return nil
        }
        
        let effort: Components.Schemas.ReasoningEffort? = switch String(describing: level) {
        case "light": .low
        case "moderate": .medium
        case "deep": .high
        default: nil
        }
        
        guard let effort else {
            return nil
        }
        
        return Components.Schemas.Reasoning(effort: effort)
    }
    
    private static func responseTextConfiguration(
        schema: GenerationSchema?
    ) -> CreateModelResponseQuery.TextResponseConfigurationOptions? {
        guard let schema else {
            return nil
        }
        
        return .jsonSchema(
            .init(
                name: "schema",
                schema: .dynamicJsonSchema(schema),
                description: nil,
                strict: true
            )
        )
    }
    
    private static func responseToolChoice(
        from mode: GenerationOptions.ToolCallingMode?
    ) -> Components.Schemas.ToolChoiceParam? {
        switch mode {
        case .allowed:
            return .ToolChoiceOptions(.auto)
        case .required:
            return .ToolChoiceOptions(.required)
        case .disallowed:
            return .ToolChoiceOptions(.none)
        case .none:
            return nil
        default:
            return nil
        }
    }
    
    private func sendReasoningSignatureIfPresent(
        _ reasoning: Components.Schemas.ReasoningItem,
        channel: LanguageModelExecutorGenerationChannel
    ) async {
        guard let encryptedContent = reasoning.encryptedContent,
              let signature = encryptedContent.data(using: .utf8) else {
            return
        }
        
        await channel.send(
            .reasoning(
                entryID: reasoning.id,
                action: .updateSignature(
                    signature,
                    tokenCount: max(1, encryptedContent.count / 4)
                )
            )
        )
    }
    
    private func flushResponseToolCallIfPossible(
        _ state: ResponseStreamingToolCallState,
        channel: LanguageModelExecutorGenerationChannel
    ) async -> Bool {
        guard !state.hasFlushed,
              let id = state.id,
              let name = state.name,
              !state.pendingArguments.isEmpty else {
            return false
        }
        
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
        return true
    }
    
    private func sendResponseUsage(
        _ usage: Components.Schemas.ResponseUsage,
        channel: LanguageModelExecutorGenerationChannel
    ) async {
        await channel.send(
            .response(
                action: .updateUsage(
                    input: .init(
                        totalTokenCount: usage.inputTokens,
                        cachedTokenCount: usage.inputTokensDetails.cachedTokens
                    ),
                    output: .init(
                        totalTokenCount: usage.outputTokens,
                        reasoningTokenCount: usage.outputTokensDetails.reasoningTokens
                    )
                )
            )
        )
    }
    
    private struct ResponseStreamingToolCallState {
        var id: String?
        var name: String?
        var pendingArguments = ""
        var hasFlushed = false
    }
}
