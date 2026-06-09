import Testing
import FoundationModels
import Foundation
@testable import FoundationDeepSeek
import OpenAI

@Suite struct DeepSeekModelTests {
    @Test func execute() async throws {
        let session = LanguageModelSession(model: DeepSeekLanguageModel.flash) {
            "When the user says Hello, world!, reply with exactly true and no other text."
        }
        
        let result = try await session.respond(to: "Hello, world!")
        let normalizedContent = result.content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "`\"'"))
            .lowercased()
        
        #expect(normalizedContent == "true")
    }
    
    @Test func factoryMethodsUseExpectedConfigurations() {
        let defaultModel = DeepSeekLanguageModel.default(apiKey: "test-key")
        let flashModel = DeepSeekLanguageModel.flash(apiKey: "test-key")
        let proModel = DeepSeekLanguageModel.pro(apiKey: "test-key")
        
        #expect(defaultModel.executorConfiguration.apiKey == "test-key")
        #expect(defaultModel.executorConfiguration.modelID == .flash)
        #expect(flashModel.executorConfiguration.apiKey == "test-key")
        #expect(flashModel.executorConfiguration.modelID == .flash)
        #expect(proModel.executorConfiguration.apiKey == "test-key")
        #expect(proModel.executorConfiguration.modelID == .pro)
    }
    
    @Test func modelStoresExecutorConfiguration() {
        let configuration = DeepSeekLanguageModelExecutor.Configuration(
            apiKey: "test-key",
            modelID: .flash
        )
        
        let model = DeepSeekLanguageModel(configuration: configuration)
        
        #expect(model.executorConfiguration == configuration)
    }
    
    @Test func executorRejectsBlankAPIKey() {
        do {
            _ = try DeepSeekLanguageModelExecutor(configuration: .init(apiKey: " \n\t "))
            Issue.record("Expected blank API key to throw.")
        } catch DeepSeekLanguageModelExecutor.DeepSeekError.emptyAPIKey {
            return
        } catch {
            Issue.record("Expected emptyAPIKey, got \(error).")
        }
    }
    
    @Test func messageTransformerPreservesTranscriptOrderAndRoles() async throws {
        let executor = try DeepSeekLanguageModelExecutor(configuration: .init(apiKey: "test-key"))
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
        
        let messages = try await executor.messageTransformer(transcript)
        
        #expect(messages.count == 5)
        #expect(systemText(messages[0]) == "Follow the developer instruction.")
        #expect(userText(messages[1]) == "What should I do?")
        #expect(assistantText(messages[2]) == "You should write a test.")
        #expect(assistantToolCall(messages[3]) == ToolCallSnapshot(id: "call_1", name: "lookup", arguments: "{\"query\": \"Swift Testing\"}"))
        #expect(toolText(messages[4]) == "Found docs.")
        #expect(toolCallID(messages[4]) == "call_1")
    }
    
    @Test func entryTransformerMapsTextEntries() throws {
        let executor = try DeepSeekLanguageModelExecutor(configuration: .init(apiKey: "test-key"))
        
        let developer = try executor.entryTransformer(
            .instructions(.init(segments: [.text(.init(content: "Be concise."))], toolDefinitions: []))
        )
        let user = try executor.entryTransformer(
            .prompt(.init(segments: [.text(.init(content: "Hello"))]))
        )
        let assistant = try executor.entryTransformer(
            .response(.init(segments: [.text(.init(content: "Hi"))]))
        )
        let tool = try executor.entryTransformer(
            .toolOutput(.init(id: "call_2", toolName: "lookup", segments: [.text(.init(content: "42"))]))
        )
        
        #expect(developer.map(systemText) == "Be concise.")
        #expect(user.map(userText) == "Hello")
        #expect(assistant.map(assistantText) == "Hi")
        #expect(tool.map(toolText) == "42")
        #expect(tool.map(toolCallID) == "call_2")
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
