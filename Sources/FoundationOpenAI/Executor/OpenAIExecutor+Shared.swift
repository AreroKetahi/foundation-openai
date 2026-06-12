//
//  OpenAIExecutor+Shared.swift
//  foundation-openai
//
//  Created by Arkivili Collindort on 11/06/2026
//

import Foundation
import FoundationModels
import OpenAI

extension OpenAILanguageModelExecutor {
    func makeOpenAIClient(model: Model) -> OpenAI {
        OpenAI(
            configuration: .init(
                token: model.apiKey,
                host: model.baseURL.host() ?? "",
                basePath: model.baseURL.path()
            ),
            middlewares: [
                ExecutorRequestModifierMiddleware(modifiers: configuration.modifiers)
            ]
        )
    }
    
    enum _SchemaVariant {
        case regular
        case containSchemaInPrompt(schema: String)
    }
    
    func makeOutputSchemaPrompt(with schema: _SchemaVariant) -> String {
        let sythesizedSchema: String? = if case .containSchemaInPrompt(let schema) = schema {
            """
            Schema:
            
            \(schema)
            """
        } else {
            nil
        }
        
        let result = """
            You are generating machine-readable structured data.
            
            The response MUST be a valid JSON object matching the provided schema.
            
            Your response MUST:
            1. Return exactly one JSON object.
            2. No markdown.
            3. No code fences.
            4. No explanations.
            5. No natural language outside JSON.
            6. Include all required properties.
            7. Do not invent properties not defined in the schema.
            8. Ensure all values conform to the schema types.
            9. The response must be directly parseable by JSONDecoder.
            
            \(sythesizedSchema ?? "") Synthesis
            """
        
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
