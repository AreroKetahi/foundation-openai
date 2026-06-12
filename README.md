# FoundationOpenAI

FoundationOpenAI bridges Apple's `FoundationModels` APIs to OpenAI-compatible 
remote model APIs.

It lets you use a remote model through the same `LanguageModelSession` style 
API that `FoundationModels` uses, while the framework handles transcript 
conversion, streaming responses, structured output, tool calling, reasoning 
output, and request customization.

> [!WARNING]
> This project currently depends on APIs introduced in OS 27 at WWDC 26. Those 
> APIs are still in beta. FoundationOpenAI will continue to evolve alongside 
> system beta releases, but it does not provide any stability guarantees at 
> this stage.

## Usage

Add the package to your Swift package dependencies:

```swift
.package(url: "https://github.com/AreroKetahi/foundation-openai", branch: "main")
```

Then add the product to your target:

```swift
.product(name: "FoundationOpenAI", package: "foundation-openai")
```

Import both `FoundationModels` and `FoundationOpenAI`:

```swift
import FoundationModels
import FoundationOpenAI
```

Create a `ChatGPTLanguageModel` and use it with `LanguageModelSession`:

```swift
let model = ChatGPTLanguageModel.v5_4mini(
    apiKey: "<OPENAI_API_KEY>"
)

let session = LanguageModelSession(model: model) {
    "You are a concise assistant."
}

let response = try await session.respond(to: "Explain FoundationOpenAI in one sentence.")
print(response.content)

// or use streaming response
for try await response in session.streamResponse(
    to: "Explain FoundationOpenAI in one sentence."
) {
    // do somethings...
}
```

`ChatGPTLanguageModel` uses OpenAI's Responses API format by default:

```swift
public var baseURL = URL(string: "https://api.openai.com/v1")!
public let apiFormat: OpenAILanguageModelAPIFormat = .response
```

The predefined ChatGPT model IDs are:

```swift
.v5_4
.v5_4mini
.v5_5
```

### Custom executor configuration

Most usage can keep the default configuration:

```swift
configuration: .default
```

Use a custom configuration when you need to change transcript conversion, 
request behavior, or tool-call strictness:

```swift
let model = ChatGPTLanguageModel(
    configuration: .init(
        toolCallingGenerationStrictness: .strict,
        transformer: DefaultQueryTransformer(),
        modifiers: []
    ),
    model: .v5_4mini,
    apiKey: "<OPENAI_API_KEY>"
)
```

`QueryTransformer` controls how `Transcript` entries are converted into 
OpenAI-compatible messages. `ExecutorRequestModifier` allows you modify the 
outgoing `URLRequest` before it is sent.

## Implementing Your Own Model

To add another OpenAI-compatible provider or model family, create a type that
 conforms to `OpenAILanguageModel`.

The type must provide:

- `Executor`: normally `OpenAILanguageModelExecutor<Self>`.
- `Model`: a `RawRepresentable` model enum whose raw value is the remote API 
  model ID.
- `capabilities`: the `FoundationModels` capabilities supported by the model.
- `baseURL`: the provider API base URL.
- `apiFormat`: `.response` for OpenAI Responses API, or `.chatCompletion` for 
  Chat Completions-compatible APIs.
- `executorConfiguration`: executor customization.
- `model`: the selected model case.
- `apiKey`: the provider API key.

Example:

```swift
import Foundation
import FoundationModels
import FoundationOpenAI

public struct MyProviderLanguageModel: OpenAILanguageModel {
    public typealias Executor = OpenAILanguageModelExecutor<MyProviderLanguageModel>

    public enum Model: String, Sendable, CaseIterable {
        case fast = "my-provider-fast"
        case pro = "my-provider-pro"
    }

    public let capabilities = LanguageModelCapabilities(
        capabilities: [.reasoning, .toolCalling, .guidedGeneration]
    )

    public let baseURL = URL(string: "https://api.example.com/v1")!
    public let apiFormat: OpenAILanguageModelAPIFormat = .chatCompletion

    public var executorConfiguration: Executor.Configuration
    public var model: Model
    public var apiKey: String

    public init(
        configuration: Executor.Configuration = .init(),
        model: Model,
        apiKey: String
    ) {
        self.executorConfiguration = configuration
        self.model = model
        self.apiKey = apiKey
    }
}
```

Then use it exactly like the predefined models:

```swift
let model = MyProviderLanguageModel(
    model: .fast,
    apiKey: "<API_KEY>"
)

let session = LanguageModelSession(model: model) {
    "You are a helpful assistant."
}

let response = try await session.respond(to: "Hello")
print(response.content)
```

If the provider follows the standard Chat Completions shape, `.chatCompletion`
plus `DefaultQueryTransformer` is usually enough. If the provider has custom 
message, tool, or request requirements, provide your own `QueryTransformer` or 
`ExecutorRequestModifier` through `Executor.Configuration`.
