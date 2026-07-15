//
//  ChatGPTLanguageModel.swift
//  foundation-openai
//
//  Created by Arkivili Collindort on 11/06/2026
//

import FoundationModels
import Foundation

@available(anyAppleOS 27.0, *)
public struct ChatGPTLanguageModel: OpenAILanguageModel {
    public typealias Executor = OpenAILanguageModelExecutor<ChatGPTLanguageModel>
    
    public enum Model: String, CaseIterable, Sendable {
        case v5_4 = "gpt-5.4"
        case v5_4mini = "gpt-5.4-mini"
        case v5_5 = "gpt-5.5"
    }
    
    public let capabilities = LanguageModelCapabilities(
        [.reasoning, .toolCalling, .vision, .guidedGeneration]
    )
    public var baseURL = URL(string: "https://api.openai.com/v1")!
    public let apiFormat: OpenAILanguageModelAPIFormat = .response
    
    public var executorConfiguration: Executor.Configuration
    public var model: Model
    public var apiKey: String

    /// Create a ChatGPT language model instance.
    /// - Parameters:
    ///   - configuration: OpenAI API configurations.
    ///   - model: Model variant.
    public init(configuration: Executor.Configuration, model: Model, apiKey: String) {
        self.executorConfiguration = configuration
        self.model = model
        self.apiKey = apiKey
    }
    
    static func v5_4(apiKey: String) -> Self {
        .init(configuration: .init(), model: .v5_4, apiKey: apiKey)
    }
    
    static func v5_4mini(apiKey: String) -> Self {
        .init(configuration: .init(), model: .v5_4mini, apiKey: apiKey)
    }
    
    static func v5_5(apiKey: String) -> Self {
        .init(configuration: .init(), model: .v5_5, apiKey: apiKey)
    }
}
