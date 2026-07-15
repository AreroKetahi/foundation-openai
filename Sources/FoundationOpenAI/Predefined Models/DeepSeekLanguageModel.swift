//
//  DeepSeekLanguageModel.swift
//  FoundationOpenAI
//
//  Created by Arkivili Collindort on 09/06/2026
//

import FoundationModels
import Foundation

@available(anyAppleOS 27.0, *)
public struct DeepSeekLanguageModel: OpenAILanguageModel {
    
    public typealias Executor = OpenAILanguageModelExecutor<DeepSeekLanguageModel>
    
    /// DeepSeek Remote Models.
    public enum Model: String, Sendable, CaseIterable {
        case flash = "deepseek-v4-flash"
        case pro = "deepseek-v4-pro"
        
        /// Typealias of non-reasoning mode DeepSeek v4 Flash model.
        ///
        /// - Important: This model will deprecated at 24 April of 2026. Use ``flash`` instead.
        @available(*, deprecated, renamed: "flash", message: "This model will deprecated at 24 April of 2026.")
        public static var chat: Self {
            .flash
        }
        
        /// Typealias of reasoning mode DeepSeek v4 Flash model.
        ///
        /// - Important: This model will deprecated at 24 April of 2026. Use ``flash`` instead.
        @available(*, deprecated, renamed: "flash", message: "This model will deprecated at 24 April of 2026.")
        public static var reasoner: Self {
            .flash
        }
    }


    public let capabilities: LanguageModelCapabilities = .init([
        .guidedGeneration,
        .reasoning,
        .toolCalling,
    ])
    public let baseURL = URL(string: "https://api.deepseek.com")!
    public let apiFormat: OpenAILanguageModelAPIFormat = .chatCompletion
    
    public var executorConfiguration: Executor.Configuration
    public var model: Model
    public let apiKey: String

    /// Create a DeepSeek language model instance.
    /// - Parameters:
    ///   - configuration: OpenAI API configurations.
    ///   - model: Model variant.
    public init(configuration: Executor.Configuration, model: Model, apiKey: String) {
        self.executorConfiguration = configuration
        self.model = model
        self.apiKey = apiKey
    }

    /// Setup a certain model.
    /// - Parameters:
    ///   - apiKey: Access API key. Generated from https://platform.deepseek.com/api_keys\.
    ///   - model: Model type.
    /// - Returns: Initialized a specified model with default configurations.
    public static func `default`(apiKey: String, model: Model) -> Self {
        return .init(configuration: .init(), model: model, apiKey: apiKey)
    }
    
    /// Setup a `deepseek-v4-pro` model.
    /// - Parameters:
    ///   - apiKey: Access API key. Generated from https://platform.deepseek.com/api_keys\.
    /// - Returns: Initialized pro model with default configurations.
    public static func pro(apiKey: String) -> Self {
        return .init(configuration: .init(), model: .pro, apiKey: apiKey)
    }
    
    /// Setup a `deepseek-v4-flash` model.
    /// - Parameters:
    ///   - apiKey: Access API key. Generated from https://platform.deepseek.com/api_keys\.
    /// - Returns: Initialized pro model with default configurations.
    public static func flash(apiKey: String) -> Self {
        return .init(configuration: .init(), model: .flash, apiKey: apiKey)
    }
}
