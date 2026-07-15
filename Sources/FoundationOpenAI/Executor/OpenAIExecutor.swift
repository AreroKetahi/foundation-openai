//
//  OpenAIExecutor.swift
//  FoundationOpenAI
//
//  Created by Arkivili Collindort on 09/06/2026
//

import Foundation
import FoundationModels
import OpenAI

/// An generalized executor that compatiable with most OpenAI API based LLMs.
///
/// You can defined your own model by implementing ``OpenAILanguageModel``.
/// We suggest you read model documentation carefully before you implement your
/// own models.
///
/// OpenAI API compatiable model may have some difference. You can pass your
/// own ``QueryTransformer`` and ``ExecutorRequestModifier`` into
/// ``Configuration`` to customize executor's behaviors.
@available(anyAppleOS 27.0, *)
public struct OpenAILanguageModelExecutor<LanguageModel: OpenAILanguageModel>: LanguageModelExecutor {
    public typealias Model = LanguageModel
    public struct Configuration: Hashable, Sendable {
        public enum GenerationStrictness: Sendable {
            case tolerant, strict
        }
        public var toolCallingGenerationStrictness: GenerationStrictness
        public var transformer: AnyQueryTransformer
        public var modifiers: [AnyExecutorRequestModifier]
        
        /// Create a configuration.
        /// - Parameters:
        ///   - apiKey: Remote model access API Key.
        ///   - baseURL: Remote model base URL.
        ///   - modelID: Model ID.
        ///   - transformer: Transcript transformer that bridge Foundation Models Transcript into OpenAI API message.
        ///   - modifiers: `URLRequest` modifiers.
        ///
        /// - Important: `modifiers` is order sensitive. It will modifying `URLRequest` in array order.
        public init<Transformer>(
            toolCallingGenerationStrictness: GenerationStrictness = .tolerant,
            transformer: Transformer = DefaultQueryTransformer(),
            modifiers: [AnyExecutorRequestModifier] = []
        ) where Transformer: QueryTransformer {
            self.toolCallingGenerationStrictness = toolCallingGenerationStrictness
            self.transformer = .init(transformer)
            self.modifiers = modifiers
        }
        
        /// Default executor configuration.
        public static var `default`: Self {
            .init()
        }
    }
    
    /// Errors that executor may throws.
    public enum OpenAIError: LocalizedError {
        case invalidResponse
        case requestFailed(statusCode: Int, body: String)
        case emptyAPIKey
        case missingModelID

        public var errorDescription: String? {
            switch self {
            case .invalidResponse:
                "API returned an invalid response."
            case .requestFailed(let statusCode, let body):
                "API request failed with status \(statusCode): \(body)"
            case .emptyAPIKey:
                "API key is empty."
            case .missingModelID:
                "Model ID is missing."
            }
        }
    }

    let configuration: Configuration
    let decoder = JSONDecoder()
    let encoder = JSONEncoder()

    public init(configuration: Configuration) throws {
        self.configuration = configuration
    }

    public func prewarm(model: Model, transcript: Transcript) {
        // Remote API model: nothing to preload locally.
    }

    public func respond(
        to request: LanguageModelExecutorGenerationRequest,
        model: Model,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        switch model.apiFormat {
        case .chatCompletion:
            try await self._chatCompletion(to: request, model: model, streamingInto: channel)
        case .response:
            try await self._response(to: request, model: model, streamingInto: channel)
        }
    }
}
