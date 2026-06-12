//
//  AnyQueryTransformer.swift
//  foundation-openai
//
//  Created by Arkivili Collindort on 10/06/2026
//

import OpenAI
import FoundationModels

public struct AnyQueryTransformer {
    var erased: any QueryTransformer
    
    public init<Transformer: QueryTransformer>(_ anyTransformer: Transformer) {
        self.erased = anyTransformer
    }
    
    public init(_ anyTransformer: any QueryTransformer) {
        self.erased = anyTransformer
    }
    
    public init(_ anyTransformer: AnyQueryTransformer) {
        self = anyTransformer
    }
    
    public func hash(into hasher: inout Hasher) {
        erased.hash(into: &hasher)
    }
    
    public static func == (lhs: borrowing AnyQueryTransformer, rhs: borrowing AnyQueryTransformer) -> Bool {
        lhs.erased.hashValue == rhs.erased.hashValue
    }
}

extension AnyQueryTransformer: QueryTransformer {
    public func transformInstructions(from instructions: Transcript.Instructions) throws -> ChatQuery.ChatCompletionMessageParam? {
        try erased.transformInstructions(from: instructions)
    }
    
    public func transformPrompt(from prompt: Transcript.Prompt) throws -> ChatQuery.ChatCompletionMessageParam? {
        try erased.transformPrompt(from: prompt)
    }
    
    public func transformResponse(from response: Transcript.Response) throws -> ChatQuery.ChatCompletionMessageParam? {
        try erased.transformResponse(from: response)
    }
    
    public func transformReasoning(from reasoning: Transcript.Reasoning) throws -> ChatQuery.ChatCompletionMessageParam? {
        try erased.transformReasoning(from: reasoning)
    }
    
    public func transformToolCalls(from toolCalls: Transcript.ToolCalls) throws -> ChatQuery.ChatCompletionMessageParam? {
        try erased.transformToolCalls(from: toolCalls)
    }
    
    public func transformToolOutput(from toolOutput: Transcript.ToolOutput) throws -> ChatQuery.ChatCompletionMessageParam? {
        try erased.transformToolOutput(from: toolOutput)
    }
}
