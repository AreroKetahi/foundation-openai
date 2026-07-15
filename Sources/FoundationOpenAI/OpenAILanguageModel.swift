//
//  OpenAILanguageModel.swift
//  foundation-openai
//
//  Created by Arkivili Collindort on 10/06/2026
//

import FoundationModels
import Foundation

@available(anyAppleOS 27.0, *)
public protocol OpenAILanguageModel: LanguageModel {
    associatedtype Model: RawRepresentable & Sendable where Model.RawValue == String
    
    var model: Model { get }
    var apiKey: String { get }
    var baseURL: URL { get }
    var apiFormat: OpenAILanguageModelAPIFormat { get }
}

/// The OpenAI API format that certain model required to.
@available(anyAppleOS 27.0, *)
public enum OpenAILanguageModelAPIFormat: Sendable {
    /// Most industry adoped API format.
    case chatCompletion
    
    /// OpenAI new generation API, that ChatGPT 5 generation recommended.
    case response
}
