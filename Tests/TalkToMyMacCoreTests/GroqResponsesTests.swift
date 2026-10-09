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
        try GroqResponses.parseOutputText(Data(json.utf8))
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

    func testModelCatalogIsGptOss20bOnly() {
        XCTAssertEqual(GroqModel.allCases.map(\.rawValue), ["openai/gpt-oss-20b"])
    }

    func testProviderDefaultsToOnDevice() {
        XCTAssertEqual(FormattingProvider.default, .appleOnDevice)
    }
}
