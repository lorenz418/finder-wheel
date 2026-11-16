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
        let body: [String: Any] = ["model": "mistral-ocr-latest", "document": document, "include_image_base64": true]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: .withoutEscapingSlashes)
        return request
    }

    /// A figure Mistral found on a page. The corners are in pixels of the page as Mistral
    /// rendered it (see `OCRPage.Dimensions`), measured from the top left.
    struct OCRImage: Decodable, Equatable {
        let id: String
        var topLeftX: Double?
        var topLeftY: Double?
        var bottomRightX: Double?
        var bottomRightY: Double?
        /// Mistral's own, low-resolution cut-out, as a data URL or plain base64.
        var imageBase64: String?

        enum CodingKeys: String, CodingKey {
            case id
            case topLeftX = "top_left_x", topLeftY = "top_left_y"
            case bottomRightX = "bottom_right_x", bottomRightY = "bottom_right_y"
            case imageBase64 = "image_base64"
        }
    }

    struct OCRPage: Decodable, Equatable {
        struct Dimensions: Decodable, Equatable {
            var dpi: Double?
            var width: Double?
            var height: Double?
        }
        let index: Int
        let markdown: String
        var images: [OCRImage]?
        var dimensions: Dimensions?
    }

    private struct OCRResponse: Decodable {
        let pages: [OCRPage]
    }

    /// Returns the pages in page order. Throws if none of them has any text.
    static func parse(data: Data, status: Int) throws -> [OCRPage] {
        guard (200..<300).contains(status) else {
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            // Validation errors (422) carry `detail` as an array of objects with a `msg`.
            let detailMessages = (json?["detail"] as? [[String: Any]])?.compactMap { $0["msg"] as? String } ?? []
            let message = (json?["message"] as? String)
                ?? (json?["detail"] as? String)
                ?? (detailMessages.isEmpty ? nil : detailMessages.joined(separator: "; "))
                ?? "request failed"
            throw ActionError("Mistral: \(message) (HTTP \(status))")
        }
        guard let response = try? JSONDecoder().decode(OCRResponse.self, from: data) else {
            throw ActionError("Mistral returned an unexpected response")
        }
        let pages = response.pages.sorted { $0.index < $1.index }
        guard pages.contains(where: { !$0.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw ActionError("Mistral returned no text")
        }
        return pages
    }
}
