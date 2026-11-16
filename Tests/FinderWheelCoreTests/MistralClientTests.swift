import Testing
import Foundation
@testable import FinderWheelCore

@Suite struct MistralClientTests {
    private func json(_ request: URLRequest) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any] ?? [:]
    }

    @Test func buildsPDFRequest() throws {
        let request = try MistralClient.makeRequest(apiKey: "key-1", data: Data("pdf".utf8), mimeType: "application/pdf")
        #expect(request.url?.absoluteString == "https://api.mistral.ai/v1/ocr")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer key-1")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try json(request)
        #expect(body["model"] as? String == "mistral-ocr-latest")
        #expect(body["include_image_base64"] as? Bool == true)
        let document = body["document"] as? [String: String]
        #expect(document?["type"] == "document_url")
        #expect(document?["document_url"] == "data:application/pdf;base64,\(Data("pdf".utf8).base64EncodedString())")
    }

    @Test func buildsImageRequest() throws {
        let request = try MistralClient.makeRequest(apiKey: "k", data: Data("img".utf8), mimeType: "image/png")
        let document = try json(request)["document"] as? [String: String]
        #expect(document?["type"] == "image_url")
        #expect(document?["image_url"] == "data:image/png;base64,\(Data("img".utf8).base64EncodedString())")
    }

    @Test func rejectsOversizedFiles() {
        let big = Data(count: 50 * 1024 * 1024 + 1)
        #expect(throws: ActionError("Larger than Mistral's 50 MB limit")) {
            _ = try MistralClient.makeRequest(apiKey: "k", data: big, mimeType: "application/pdf")
        }
    }

    @Test func parsesPagesInIndexOrder() throws {
        // Two pound signs: the JSON contains `"#`, which would end a single-pound raw string.
        let body = ##"{"pages":[{"index":1,"markdown":"second"},{"index":0,"markdown":"# first"}]}"##
        #expect(try MistralClient.parse(data: Data(body.utf8), status: 200).map(\.markdown) == ["# first", "second"])
    }

    @Test func parsesImagesAndDimensions() throws {
        let body = #"""
        {"pages":[{"index":0,"markdown":"![img-0.jpeg](img-0.jpeg)",
          "images":[{"id":"img-0.jpeg","top_left_x":10,"top_left_y":20,"bottom_right_x":110,"bottom_right_y":70,"image_base64":"data:image/jpeg;base64,QUJD"}],
          "dimensions":{"dpi":200,"height":2200,"width":1700}}]}
        """#
        let page = try #require(try MistralClient.parse(data: Data(body.utf8), status: 200).first)
        #expect(page.dimensions == .init(dpi: 200, width: 1700, height: 2200))
        #expect(page.images == [.init(id: "img-0.jpeg", topLeftX: 10, topLeftY: 20, bottomRightX: 110, bottomRightY: 70,
                                      imageBase64: "data:image/jpeg;base64,QUJD")])
    }

    @Test func emptyResultIsAnError() {
        #expect(throws: ActionError("Mistral returned no text")) {
            _ = try MistralClient.parse(data: Data(#"{"pages":[]}"#.utf8), status: 200)
        }
        #expect(throws: ActionError("Mistral returned no text")) {
            _ = try MistralClient.parse(data: Data(#"{"pages":[{"index":0,"markdown":"  "}]}"#.utf8), status: 200)
        }
    }

    @Test func errorsCarryTheServerMessage() {
        #expect(throws: ActionError("Mistral: Unauthorized (HTTP 401)")) {
            _ = try MistralClient.parse(data: Data(#"{"message":"Unauthorized"}"#.utf8), status: 401)
        }
        #expect(throws: ActionError("Mistral: Rate limit exceeded (HTTP 429)")) {
            _ = try MistralClient.parse(data: Data(#"{"detail":"Rate limit exceeded"}"#.utf8), status: 429)
        }
        #expect(throws: ActionError("Mistral: first; second (HTTP 422)")) {
            _ = try MistralClient.parse(data: Data(#"{"detail":[{"loc":["a"],"msg":"first"},{"loc":["b"],"msg":"second"}]}"#.utf8), status: 422)
        }
        #expect(throws: ActionError("Mistral: request failed (HTTP 500)")) {
            _ = try MistralClient.parse(data: Data("<html>".utf8), status: 500)
        }
    }
}
