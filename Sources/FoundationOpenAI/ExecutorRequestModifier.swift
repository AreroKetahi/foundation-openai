//
//  ExecutorRequestModifier.swift
//  foundation-openai
//
//  Created by Arkivili Collindort on 10/06/2026
//

import Foundation

/// An modifier that can modify `HTTPRequest` to model API.
///
/// By implement this protocol, you can dynamicly edit out request before it send.
///
/// ```swift
/// struct MyRequestModifier: ExecutorRequestModifier {
///     func modify(_ request: URLRequest) -> URLRequest {
///         // mutating request here...
///     }
/// }
/// ```
@available(anyAppleOS 27.0, *)
public protocol ExecutorRequestModifier: Hashable, Sendable {
    /// Modify `URLRequest` in runtime.
    /// - Parameter request: Original `URLRequest` that needs to modify.
    func modify(_ request: inout URLRequest)
}

/// An container type that wrapping all the ``ExecutorRequestModifier``.
@available(anyAppleOS 27.0, *)
public struct AnyExecutorRequestModifier: ExecutorRequestModifier {
    private let erased: any ExecutorRequestModifier
    private let hashInto: @Sendable (inout Hasher) -> Void
    private let isEqual: @Sendable (any ExecutorRequestModifier) -> Bool
    
    /// Wrapping a modifier.
    /// - Parameter modifier: Modifier.
    public init<Modifier: ExecutorRequestModifier>(_ modifier: Modifier) {
        self.erased = modifier
        self.hashInto = { hasher in
            hasher.combine(ObjectIdentifier(Modifier.self))
            modifier.hash(into: &hasher)
        }
        self.isEqual = { other in
            guard let other = other as? Modifier else {
                return false
            }
            
            return modifier == other
        }
    }
    
    public init(_ modifier: AnyExecutorRequestModifier) {
        self = modifier
    }
    
    public func modify(_ request: inout URLRequest) {
        erased.modify(&request)
    }
    
    public func hash(into hasher: inout Hasher) {
        hashInto(&hasher)
    }
    
    public static func == (lhs: AnyExecutorRequestModifier, rhs: AnyExecutorRequestModifier) -> Bool {
        lhs.isEqual(rhs.erased)
    }
}
