import Foundation
import XCTest
@testable import TalkToMyMacCore

final class OpenRouterResponsesTests: XCTestCase {

    // MARK: Request

    private func makeRequest() -> URLRequest {
        OpenRouterResponses.makeRequest(apiKey: "sk-or-test", model: .nemotron35Lightning,
                                        instructions: "Clean this up.", input: "<transcript>\nhi\n</transcript>")
    }

    private func body(of request: URLRequest) throws -> [String: Any] {
        let data = try XCTUnwrap(request.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testRequestTargetsChatCompletionsEndpoint() {
        let request = makeRequest()
        XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/chat/completions")
        XCTAssertEqual(request.httpMethod, "POST")
    }

    func testRequestHeaders() {
        let request = makeRequest()
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-or-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-OpenRouter-Title"), "TalkToMyMac")
    }

    func testRequestBody() throws {
        let body = try body(of: makeRequest())
        XCTAssertEqual(body["model"] as? String, "nvidia/nemotron-3.5-lightning:free")
        XCTAssertEqual(body["temperature"] as? Double, 0.2)
        XCTAssertEqual(body["max_tokens"] as? Int, 2048)
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0]["role"] as? String, "system")
        XCTAssertEqual(messages[0]["content"] as? String, "Clean this up.")
        XCTAssertEqual(messages[1]["role"] as? String, "user")
        XCTAssertEqual(messages[1]["content"] as? String, "<transcript>\nhi\n</transcript>")
    }

    // MARK: Response parsing

    private func parse(_ json: String, statusCode: Int = 200) throws -> String {
        try OpenRouterResponses.parse(Data(json.utf8), statusCode: statusCode).text
    }

    func testParsesMessageContent() throws {
        let json = """
        {"id": "gen-1", "choices": [
          {"finish_reason": "stop", "message": {"role": "assistant", "content": "Hello, world."}}
        ]}
        """
        XCTAssertEqual(try parse(json), "Hello, world.")
    }

    func testParsesTokenUsage() throws {
        let json = """
        {"choices": [{"finish_reason": "stop", "message": {"content": "Hi."}}],
         "usage": {"prompt_tokens": 82, "prompt_tokens_details": {"cached_tokens": 10},
                   "completion_tokens": 266, "completion_tokens_details": {"reasoning_tokens": 200},
                   "total_tokens": 348}}
        """
        let output = try OpenRouterResponses.parse(Data(json.utf8), statusCode: 200)
        XCTAssertEqual(output.usage, TokenUsage(input: 82, output: 266, reasoning: 200, cached: 10))
    }

    func testMissingUsageDetailsDefaultToZero() throws {
        let json = """
        {"choices": [{"finish_reason": "stop", "message": {"content": "Hi."}}],
         "usage": {"prompt_tokens": 5, "completion_tokens": 7, "total_tokens": 12}}
        """
        XCTAssertEqual(try OpenRouterResponses.parse(Data(json.utf8), statusCode: 200).usage,
                       TokenUsage(input: 5, output: 7, reasoning: 0, cached: 0))
    }

    func testMissingUsageIsNil() throws {
        let json = """
        {"choices": [{"finish_reason": "stop", "message": {"content": "Hi."}}]}
        """
        XCTAssertNil(try OpenRouterResponses.parse(Data(json.utf8), statusCode: 200).usage)
    }

    func testUsageReadableFromTruncatedResponse() {
        let json = """
        {"choices": [{"finish_reason": "length", "message": {"content": "Hel"}}],
         "usage": {"prompt_tokens": 90, "completion_tokens": 2048}}
        """
        XCTAssertEqual(OpenRouterResponses.usage(in: Data(json.utf8)),
                       TokenUsage(input: 90, output: 2048, reasoning: 0, cached: 0))
        XCTAssertNil(OpenRouterResponses.usage(in: Data("not json".utf8)))
    }

    func testAPIErrorThrowsMessage() {
        let json = """
        {"error": {"code": 401, "message": "No auth credentials found"}}
        """
        XCTAssertThrowsError(try parse(json, statusCode: 401)) { error in
            XCTAssertEqual(error as? OpenRouterError, .api("No auth credentials found"))
        }
    }

    func testChoiceErrorThrowsMessage() {
        let json = """
        {"choices": [{"finish_reason": "error", "native_finish_reason": "error",
          "error": {"code": 502, "message": "Provider returned error"},
          "message": {"content": ""}}]}
        """
        XCTAssertThrowsError(try parse(json)) { error in
            XCTAssertEqual(error as? OpenRouterError, .api("Provider returned error"))
        }
    }

    func testErrorFinishReasonWithoutMessageThrows() {
        let json = """
        {"choices": [{"finish_reason": "error", "message": {"content": null}}]}
        """
        XCTAssertThrowsError(try parse(json)) { error in
            XCTAssertEqual(error as? OpenRouterError, .api("The model returned an error"))
        }
    }

    func testLengthFinishReasonThrowsIncomplete() {
        let json = """
        {"choices": [{"finish_reason": "length", "message": {"content": "Hel"}}]}
        """
        XCTAssertThrowsError(try parse(json)) { error in
            XCTAssertEqual(error as? OpenRouterError, .incomplete("length"))
        }
    }

    func testNullContentThrowsNoText() {
        let json = """
        {"choices": [{"finish_reason": "stop", "message": {"content": null, "reasoning": "thinking"}}]}
        """
        XCTAssertThrowsError(try parse(json)) { error in
            XCTAssertEqual(error as? OpenRouterError, .noText)
        }
    }

    func testEmptyChoicesThrowsNoText() {
        XCTAssertThrowsError(try parse(#"{"choices": []}"#)) { error in
            XCTAssertEqual(error as? OpenRouterError, .noText)
        }
    }

    func testHTTPStatusWithoutErrorBodyThrowsReadableMessage() {
        XCTAssertThrowsError(try parse("", statusCode: 429)) { error in
            XCTAssertEqual(error as? OpenRouterError, .api("Rate limited by OpenRouter (HTTP 429)"))
        }
        XCTAssertThrowsError(try parse("<html>", statusCode: 401)) { error in
            XCTAssertEqual(error as? OpenRouterError, .api("Invalid OpenRouter API key (HTTP 401)"))
        }
        XCTAssertThrowsError(try parse("{}", statusCode: 402)) { error in
            XCTAssertEqual(error as? OpenRouterError, .api("OpenRouter account has insufficient credits (HTTP 402)"))
        }
        XCTAssertThrowsError(try parse("", statusCode: 503)) { error in
            XCTAssertEqual(error as? OpenRouterError, .api("OpenRouter returned HTTP 503"))
        }
    }

    func testMalformedJSONThrows() {
        XCTAssertThrowsError(try parse("not json"))
    }

    // MARK: Models

    func testModelCatalog() {
        XCTAssertEqual(OpenRouterModel.allCases.map(\.rawValue), [
            "nvidia/nemotron-3-ultra-550b-a55b:free",
            "nvidia/nemotron-3.5-lightning:free",
            "thinkingmachines/inkling-small:free",
            "google/gemma-4-26b-a4b-it:free",
            "cohere/north-mini-code:free",
            "liquid/lfm-2.5-2.6b:free",
        ])
        XCTAssertEqual(OpenRouterModel.default, .nemotron35Lightning)
    }

    func testFreeModelsListAtZero() {
        let free = TokenPrice(inputPerMillion: 0, cachedInputPerMillion: 0, outputPerMillion: 0)
        for model in OpenRouterModel.allCases {
            XCTAssertEqual(model.listPrice, free, model.rawValue)
        }
    }

    func testFormattingModelIdentity() {
        let model = FormattingModel.openRouter(.gemma4)
        XCTAssertEqual(model.provider, .openRouter)
        XCTAssertEqual(model.modelID, "google/gemma-4-26b-a4b-it:free")
        XCTAssertTrue(model.isRemote)
        XCTAssertEqual(model.displayName, "OpenRouter · google/gemma-4-26b-a4b-it:free")
    }
}
