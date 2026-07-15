//
//  QueryTransformer.swift
//  foundation-openai
//
//  Created by Arkivili Collindort on 10/06/2026
//

import Foundation
import FoundationModels
import OpenAI

/// Transform Foundation Models transcript entry into OpenAI API message.
///
/// You can **optionally** implement any transforming method that you many want to change.
/// Other methods will remains default.
@available(anyAppleOS 27.0, *)
public protocol QueryTransformer: Sendable, Hashable {
    func transformInstructions(from instructions: Transcript.Instructions) throws -> ChatQuery.ChatCompletionMessageParam?
    func transformPrompt(from prompt: Transcript.Prompt) throws -> ChatQuery.ChatCompletionMessageParam?
    func transformToolOutput(from toolOutput: Transcript.ToolOutput) throws -> ChatQuery.ChatCompletionMessageParam?
    func transformResponse(from response: Transcript.Response) throws -> ChatQuery.ChatCompletionMessageParam?
    func transformToolCalls(from toolCalls: Transcript.ToolCalls) throws -> ChatQuery.ChatCompletionMessageParam?
    func transformReasoning(from reasoning: Transcript.Reasoning) throws -> ChatQuery.ChatCompletionMessageParam?
}

/// Default transformer implementation.
@available(anyAppleOS 27.0, *)
public struct DefaultQueryTransformer: QueryTransformer {
    public init() { }
}

@available(anyAppleOS 27.0, *)
extension QueryTransformer where Self == DefaultQueryTransformer {
    /// Default query transformer.
    static var `default`: Self { .init() }
}

@available(anyAppleOS 27.0, *)
extension QueryTransformer {
    public func transformInstructions(from instructions: Transcript.Instructions) throws -> ChatQuery.ChatCompletionMessageParam? {
        .system(
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
    }
    
    public func transformPrompt(from prompt: Transcript.Prompt) throws -> ChatQuery.ChatCompletionMessageParam? {
        .user(
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
    }
    
    public func transformToolOutput(from toolOutput: Transcript.ToolOutput) throws -> ChatQuery.ChatCompletionMessageParam? {
        .tool(
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
    }
    
    public func transformResponse(from response: Transcript.Response) throws -> ChatQuery.ChatCompletionMessageParam? {
        .assistant(
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
    }
    
    public func transformToolCalls(from toolCalls: Transcript.ToolCalls) throws -> ChatQuery.ChatCompletionMessageParam? {
        .assistant(
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
    }
    
    public func transformReasoning(from reasoning: Transcript.Reasoning) throws -> ChatQuery.ChatCompletionMessageParam? {
        return nil // FIXME: Need justify
    }
}
