//
//  DeepSeekLanguageModel.swift
//  FoundationDeepSeek
//
//  Created by Arkivili Collindort on 09/06/2026
//

import FoundationModels

struct DeepSeekLanguageModel: LanguageModel {
    typealias Executor = DeepSeekLanguageModelExecutor

    let executorConfiguration: DeepSeekLanguageModelExecutor.Configuration

    let capabilities: LanguageModelCapabilities = .init(capabilities: [
        .guidedGeneration,
        .reasoning,
    ])

    init(configuration: DeepSeekLanguageModelExecutor.Configuration = .init(apiKey: DEEPSEEK_API_KEY)) {
        self.executorConfiguration = configuration
    }
    
    static func `default`(apiKey: String) -> Self {
        return .init(configuration: .init(apiKey: apiKey))
    }
    
    static var `default`: Self {
        return .init(configuration: .init(apiKey: DEEPSEEK_API_KEY))
    }
    
    static func pro(apiKey: String) -> Self {
        return .init(configuration: .init(apiKey: apiKey, modelID: .pro))
    }
    
    static var pro: Self {
        return .init(configuration: .init(apiKey: DEEPSEEK_API_KEY, modelID: .pro))
    }
    
    static func flash(apiKey: String) -> Self {
        return .init(configuration: .init(apiKey: apiKey, modelID: .flash))
    }
    
    static var flash: Self {
        return .init(configuration: .init(apiKey: DEEPSEEK_API_KEY, modelID: .flash))
    }
}
