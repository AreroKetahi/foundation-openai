//
//  ExecutorRequestModifierMiddleware.swift
//  foundation-openai
//
//  Created by Arkivili Collindort on 11/06/2026
//


import Foundation
import FoundationModels
import OpenAI

struct ExecutorRequestModifierMiddleware: OpenAIMiddleware {
    let modifiers: [AnyExecutorRequestModifier]
    
    func intercept(request: URLRequest) -> URLRequest {
        var copy = request
        modifiers.forEach { modifier in
            modifier.modify(&copy)
        }
        return copy
    }
}
