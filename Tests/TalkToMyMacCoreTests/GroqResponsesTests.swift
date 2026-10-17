import Foundation
import XCTest
@testable import TalkToMyMacCore

final class GroqResponsesTests: XCTestCase {

    // MARK: Request

    private func makeRequest() -> URLRequest {
        GroqResponses.makeRequest(apiKey: "gsk_test", model: .gptOss20b,
                                  instructions: "Clean this up.", input: "<transcript>\nhi\n</transcript>")
    }

    private func body(of request: URLRequest) throws -> [String: Any] {
        let data = try XCTUnwrap(request.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testRequestTargetsResponsesEndpoint() {
        let request = makeRequest()
        XCTAssertEqual(request.url?.absoluteString, "https://api.groq.com/openai/v1/responses")
        XCTAssertEqual(request.httpMethod, "POST")
    }

    func testRequestHeaders() {
        let request = makeRequest()
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer gsk_test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func testRequestBody() throws {
        let body = try body(of: makeRequest())
        XCTAssertEqual(body["model"] as? String, "openai/gpt-oss-20b")
        XCTAssertEqual(body["instructions"] as? String, "Clean this up.")
        XCTAssertEqual(body["input"] as? String, "<transcript>\nhi\n</transcript>")
        XCTAssertEqual(body["temperature"] as? Double, 0.2)
        XCTAssertEqual(body["max_output_tokens"] as? Int, 2048)
        XCTAssertEqual((body["reasoning"] as? [String: Any])?["effort"] as? String, "low")
    }

    // MARK: Response parsing

    private func parse(_ json: String) throws -> String {
        try GroqResponses.parse(Data(json.utf8)).text
    }

    func testParsesMessageTextSkippingReasoning() throws {
        let json = """
        {"status": "completed", "error": null, "output": [
          {"type": "reasoning", "id": "r1", "content": [{"type": "reasoning_text", "text": "thinking"}]},
          {"type": "message", "role": "assistant", "content": [
            {"type": "output_text", "text": "Hello, world.", "annotations": []}
          ]}
        ]}
        """
        XCTAssertEqual(try parse(json), "Hello, world.")
    }

    func testParsesTokenUsage() throws {
        let json = """
        {"status": "completed", "output": [
          {"type": "message", "content": [{"type": "output_text", "text": "Hi."}]}
        ], "usage": {"input_tokens": 82, "input_tokens_details": {"cached_tokens": 10},
                     "output_tokens": 266, "output_tokens_details": {"reasoning_tokens": 200},
                     "total_tokens": 348}}
        """
        let output = try GroqResponses.parse(Data(json.utf8))
        XCTAssertEqual(output.usage, TokenUsage(input: 82, output: 266, reasoning: 200, cached: 10))
    }

    func testMissingUsageDetailsDefaultToZero() throws {
        let json = """
        {"status": "completed", "output": [
          {"type": "message", "content": [{"type": "output_text", "text": "Hi."}]}
        ], "usage": {"input_tokens": 5, "output_tokens": 7}}
        """
        XCTAssertEqual(try GroqResponses.parse(Data(json.utf8)).usage,
                       TokenUsage(input: 5, output: 7, reasoning: 0, cached: 0))
    }

    func testMissingUsageIsNil() throws {
        let json = """
        {"status": "completed", "output": [
          {"type": "message", "content": [{"type": "output_text", "text": "Hi."}]}
        ]}
        """
        XCTAssertNil(try GroqResponses.parse(Data(json.utf8)).usage)
    }

    func testUsageReadableFromIncompleteResponse() {
        // A response cut off at max_output_tokens is still billed.
        let json = """
        {"status": "incomplete", "output": [], "usage": {"input_tokens": 90, "output_tokens": 2048,
         "output_tokens_details": {"reasoning_tokens": 2048}}}
        """
        XCTAssertEqual(GroqResponses.usage(in: Data(json.utf8)),
                       TokenUsage(input: 90, output: 2048, reasoning: 2048, cached: 0))
        XCTAssertNil(GroqResponses.usage(in: Data("not json".utf8)))
    }

    func testJoinsMultipleTextParts() throws {
        let json = """
        {"status": "completed", "output": [
          {"type": "message", "content": [
            {"type": "output_text", "text": "Hello, "},
            {"type": "output_text", "text": "world."}
          ]}
        ]}
        """
        XCTAssertEqual(try parse(json), "Hello, world.")
    }

    func testAPIErrorThrowsMessage() {
        let json = """
        {"error": {"message": "Invalid API Key", "type": "invalid_request_error"}}
        """
        XCTAssertThrowsError(try parse(json)) { error in
            XCTAssertEqual(error as? GroqError, .api("Invalid API Key"))
        }
    }

    func testIncompleteStatusThrows() {
        let json = """
        {"status": "incomplete", "output": [
          {"type": "message", "content": [{"type": "output_text", "text": "Hel"}]}
        ]}
        """
        XCTAssertThrowsError(try parse(json)) { error in
            XCTAssertEqual(error as? GroqError, .incomplete("incomplete"))
        }
    }

    func testNoMessageThrowsNoText() {
        let json = """
        {"status": "completed", "output": [{"type": "reasoning", "content": []}]}
        """
        XCTAssertThrowsError(try parse(json)) { error in
            XCTAssertEqual(error as? GroqError, .noText)
        }
    }

    func testMalformedJSONThrows() {
        XCTAssertThrowsError(try parse("not json"))
    }

    // MARK: Models

    func testModelCatalog() {
        XCTAssertEqual(GroqModel.allCases.map(\.rawValue), [
            "openai/gpt-oss-20b",
            "openai/gpt-oss-120b",
            "qwen/qwen3.8-27b",
        ])
        XCTAssertEqual(GroqModel.default, .gptOss20b)
    }

    func testOnlyReasoningModelsSendReasoningEffort() throws {
        XCTAssertTrue(GroqModel.gptOss20b.supportsReasoning)
        XCTAssertTrue(GroqModel.gptOss120b.supportsReasoning)
        XCTAssertFalse(GroqModel.qwen38_27b.supportsReasoning)

        // Only gpt-oss takes reasoning effort "low", so it's left out of other models' requests.
        let request = GroqResponses.makeRequest(apiKey: "gsk_test", model: .qwen38_27b,
                                                instructions: "Clean this up.", input: "hi")
        let body = try body(of: request)
        XCTAssertEqual(body["model"] as? String, "qwen/qwen3.8-27b")
        XCTAssertNil(body["reasoning"])
    }

    func testProviderDefaultsToOnDevice() {
        XCTAssertEqual(FormattingProvider.default, .appleOnDevice)
    }

    func testFormattingModelIdentity() {
        let groq = FormattingModel.groq(.gptOss20b)
        XCTAssertEqual(groq.provider, .groq)
        XCTAssertEqual(groq.modelID, "openai/gpt-oss-20b")
        XCTAssertTrue(groq.isRemote)
        XCTAssertFalse(FormattingModel.appleOnDevice.isRemote)
        XCTAssertEqual(FormattingModel.appleOnDevice.provider, .appleOnDevice)
    }
}
