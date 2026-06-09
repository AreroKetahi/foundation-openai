//
//  DeepSeekLanguageModel.swift
//  FoundationDeepSeek
//
//  Created by Arkivili Collindort on 09/06/2026
//

import FoundationModels

public struct DeepSeekLanguageModel: LanguageModel {
    public typealias Executor = DeepSeekLanguageModelExecutor

    public let executorConfiguration: DeepSeekLanguageModelExecutor.Configuration

    public let capabilities: LanguageModelCapabilities = .init(capabilities: [
        .guidedGeneration,
        .reasoning,
    ])

    public init(configuration: DeepSeekLanguageModelExecutor.Configuration) {
        self.executorConfiguration = configuration
    }
    
    public static func `default`(apiKey: String) -> Self {
        return .init(configuration: .init(apiKey: apiKey))
    }
    
    public static func pro(apiKey: String) -> Self {
        return .init(configuration: .init(apiKey: apiKey, modelID: .pro))
    }
    
    public static func flash(apiKey: String) -> Self {
        return .init(configuration: .init(apiKey: apiKey, modelID: .flash))
    }
}
