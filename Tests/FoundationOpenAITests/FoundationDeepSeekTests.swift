import Foundation
import FoundationModels
import OpenAI
import Testing
@testable import FoundationOpenAI

@Suite struct DeepSeekModelTests {
    private typealias DeepSeekExecutor = OpenAILanguageModelExecutor<DeepSeekLanguageModel>
    
    @Test func factoryMethodsUseExpectedConfigurations() throws {
        let defaultModel = DeepSeekLanguageModel.default(apiKey: "test-key", model: .flash)
        let flashModel = DeepSeekLanguageModel.flash(apiKey: "test-key")
        let proModel = DeepSeekLanguageModel.pro(apiKey: "test-key")
        
        #expect(defaultModel.executorConfiguration.apiKey == "test-key")
        #expect(defaultModel.executorConfiguration.modelID == DeepSeekLanguageModel.Model.flash.rawValue)
        #expect(flashModel.executorConfiguration.apiKey == "test-key")
        #expect(flashModel.executorConfiguration.modelID == DeepSeekLanguageModel.Model.flash.rawValue)
        #expect(proModel.executorConfiguration.apiKey == "test-key")
        #expect(proModel.executorConfiguration.modelID == DeepSeekLanguageModel.Model.pro.rawValue)
    }
    
    @Test func modelStoresExecutorConfiguration() {
        let configuration = DeepSeekExecutor.Configuration(
            apiKey: "test-key",
            baseURL: deepSeekBaseURL,
            modelID: DeepSeekLanguageModel.Model.flash.rawValue
        )
        
        let model = DeepSeekLanguageModel(configuration: configuration, model: .flash)
        
        #expect(model.executorConfiguration == configuration)
    }
    
    @Test func executorRejectsBlankAPIKey() {
        do {
            _ = try DeepSeekExecutor(
                configuration: .init(
                    apiKey: " \n\t ",
                    baseURL: deepSeekBaseURL,
                    modelID: DeepSeekLanguageModel.Model.flash.rawValue
                )
            )
            Issue.record("Expected blank API key to throw.")
        } catch DeepSeekExecutor.OpenAIError.emptyAPIKey {
            return
        } catch {
            Issue.record("Expected emptyAPIKey, got \(error).")
        }
    }
    
    @Test func messageTransformerPreservesTranscriptOrderAndRoles() async throws {
        let executor = try DeepSeekExecutor(
            configuration: .init(
                apiKey: "test-key",
                baseURL: deepSeekBaseURL,
                modelID: DeepSeekLanguageModel.Model.flash.rawValue
            )
        )
        let transcript = Transcript(entries: [
            .instructions(.init(segments: [.text(.init(content: "Follow the developer instruction."))], toolDefinitions: [])),
            .prompt(.init(segments: [.text(.init(content: "What should I do?"))])),
            .response(.init(segments: [.text(.init(content: "You should write a test."))])),
            .toolCalls(.init([
                .init(
                    id: "call_1",
                    toolName: "lookup",
                    arguments: GeneratedContent(properties: ["query": "Swift Testing"])
                )
            ])),
            .toolOutput(.init(id: "call_1", toolName: "lookup", segments: [.text(.init(content: "Found docs."))]))
        ])
        
        let messages = try await executor.messageTransformer(
            transcript,
            transformer: AnyQueryTransformer(DefaultQueryTransformer())
        )
        
        #expect(messages.count == 5)
        #expect(systemText(messages[0]) == "Follow the developer instruction.")
        #expect(userText(messages[1]) == "What should I do?")
        #expect(assistantText(messages[2]) == "You should write a test.")
        #expect(assistantToolCall(messages[3]) == ToolCallSnapshot(id: "call_1", name: "lookup", arguments: "{\"query\": \"Swift Testing\"}"))
        #expect(toolText(messages[4]) == "Found docs.")
        #expect(toolCallID(messages[4]) == "call_1")
    }
    
    @Test func entryTransformerMapsTextEntries() throws {
        let transformer = DeepSeekExecutor.Configuration(
            apiKey: "test-key",
            baseURL: deepSeekBaseURL,
            modelID: DeepSeekLanguageModel.Model.flash.rawValue
        ).transformer
        
        let developer = try DeepSeekExecutor.entryTransformer(
            .instructions(.init(segments: [.text(.init(content: "Be concise."))], toolDefinitions: [])),
            transformer: transformer
        )
        let user = try DeepSeekExecutor.entryTransformer(
            .prompt(.init(segments: [.text(.init(content: "Hello"))])),
            transformer: transformer
        )
        let assistant = try DeepSeekExecutor.entryTransformer(
            .response(.init(segments: [.text(.init(content: "Hi"))])),
            transformer: transformer
        )
        let tool = try DeepSeekExecutor.entryTransformer(
            .toolOutput(.init(id: "call_2", toolName: "lookup", segments: [.text(.init(content: "42"))])),
            transformer: transformer
        )
        
        #expect(developer.map(systemText) == "Be concise.")
        #expect(user.map(userText) == "Hello")
        #expect(assistant.map(assistantText) == "Hi")
        #expect(tool.map(toolText) == "42")
        #expect(tool.map(toolCallID) == "call_2")
    }
    
    @Test func anyExecutorRequestModifierDelegatesAndComparesByWrappedValue() throws {
        let modifier = AnyExecutorRequestModifier(HeaderModifier(field: "X-Test", value: "one"))
        var request = URLRequest(url: try #require(URL(string: "https://example.com")))
        request = modifier.requestModifier(request)
        
        #expect(request.value(forHTTPHeaderField: "X-Test") == "one")
        #expect(modifier == AnyExecutorRequestModifier(HeaderModifier(field: "X-Test", value: "one")))
        #expect(modifier != AnyExecutorRequestModifier(HeaderModifier(field: "X-Test", value: "two")))
    }
    
    @Test func configurationHashableIncludesRequestModifiers() {
        let first = DeepSeekExecutor.Configuration(
            apiKey: "test-key",
            baseURL: deepSeekBaseURL,
            modelID: DeepSeekLanguageModel.Model.flash.rawValue,
            modifiers: [AnyExecutorRequestModifier(HeaderModifier(field: "X-Test", value: "one"))]
        )
        let second = DeepSeekExecutor.Configuration(
            apiKey: "test-key",
            baseURL: deepSeekBaseURL,
            modelID: DeepSeekLanguageModel.Model.flash.rawValue,
            modifiers: [AnyExecutorRequestModifier(HeaderModifier(field: "X-Test", value: "one"))]
        )
        let different = DeepSeekExecutor.Configuration(
            apiKey: "test-key",
            baseURL: deepSeekBaseURL,
            modelID: DeepSeekLanguageModel.Model.flash.rawValue,
            modifiers: [AnyExecutorRequestModifier(HeaderModifier(field: "X-Test", value: "two"))]
        )
        
        #expect(first == second)
        #expect(first != different)
    }
}

private let deepSeekBaseURL = URL(string: "https://api.deepseek.com")!

private struct HeaderModifier: ExecutorRequestModifier {
    var field: String
    var value: String
    
    func requestModifier(_ request: URLRequest) -> URLRequest {
        var request = request
        request.setValue(value, forHTTPHeaderField: field)
        return request
    }
}

private struct ToolCallSnapshot: Equatable {
    var id: String
    var name: String
    var arguments: String
}

private func systemText(_ message: ChatQuery.ChatCompletionMessageParam) -> String? {
    guard case .system(let system) = message,
          case .contentParts(let parts) = system.content,
          let first = parts.first
    else {
        return nil
    }
    
    return first.text
}

private func userText(_ message: ChatQuery.ChatCompletionMessageParam) -> String? {
    guard case .user(let user) = message,
          case .contentParts(let parts) = user.content,
          case .text(let first)? = parts.first
    else {
        return nil
    }
    
    return first.text
}

private func assistantText(_ message: ChatQuery.ChatCompletionMessageParam) -> String? {
    guard case .assistant(let assistant) = message,
          case .contentParts(let parts)? = assistant.content,
          case .text(let first)? = parts.first
    else {
        return nil
    }
    
    return first.text
}

private func assistantToolCall(_ message: ChatQuery.ChatCompletionMessageParam) -> ToolCallSnapshot? {
    guard case .assistant(let assistant) = message,
          let toolCall = assistant.toolCalls?.first
    else {
        return nil
    }
    
    return ToolCallSnapshot(
        id: toolCall.id,
        name: toolCall.function.name,
        arguments: toolCall.function.arguments
    )
}

private func toolText(_ message: ChatQuery.ChatCompletionMessageParam) -> String? {
    guard case .tool(let tool) = message,
          case .contentParts(let parts) = tool.content,
          let first = parts.first
    else {
        return nil
    }
    
    return first.text
}

private func toolCallID(_ message: ChatQuery.ChatCompletionMessageParam) -> String? {
    guard case .tool(let tool) = message else {
        return nil
    }
    
    return tool.toolCallId
}
