import Foundation

/// Builds and interprets Mistral OCR calls. Stateless; the network is a closure.
public enum MistralClient {
    /// Sends a request and returns the body and HTTP status.
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, Int)

    public static let endpoint = URL(string: "https://api.mistral.ai/v1/ocr")!
    static let maxBytes = 50 * 1024 * 1024

    public static let urlSessionTransport: Transport = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    /// `mimeType` is "application/pdf" or an image type such as "image/jpeg".
    static func makeRequest(apiKey: String, data: Data, mimeType: String) throws -> URLRequest {
        guard data.count <= maxBytes else { throw ActionError("Larger than Mistral's 50 MB limit") }
        let dataURL = "data:\(mimeType);base64,\(data.base64EncodedString())"
        let document: [String: String] = mimeType == "application/pdf"
            ? ["type": "document_url", "document_url": dataURL]
            : ["type": "image_url", "image_url": dataURL]
        let body: [String: Any] = ["model": "mistral-ocr-latest", "document": document, "include_image_base64": false]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private struct OCRResponse: Decodable {
        struct Page: Decodable {
            let index: Int
            let markdown: String
        }
        let pages: [Page]
    }

    /// Returns the Markdown of all pages, in page order, ending with one newline.
    static func parse(data: Data, status: Int) throws -> String {
        guard (200..<300).contains(status) else {
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let message = (json?["message"] as? String) ?? (json?["detail"] as? String) ?? "request failed"
            throw ActionError("Mistral: \(message) (HTTP \(status))")
        }
        guard let response = try? JSONDecoder().decode(OCRResponse.self, from: data) else {
            throw ActionError("Mistral returned an unexpected response")
        }
        let text = response.pages.sorted { $0.index < $1.index }
            .map { $0.markdown.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        guard !text.isEmpty else { throw ActionError("Mistral returned no text") }
        return text + "\n"
    }
}
