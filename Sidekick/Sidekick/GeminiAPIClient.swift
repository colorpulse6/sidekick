import Foundation

enum GeminiAPIError: Error {
    case invalidURL
    case noData
    case decodingError
    case apiError(String)
    case unknown
}

enum GeminiResponse {
    case text(String)
    case toolCall(name: String, args: [String: Any])
}

class GeminiAPIClient {
    private let apiKey: String
    private let baseURL: String

    init(apiKey: String) {
        self.apiKey = apiKey
        self.baseURL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=\((apiKey))"
    }

    func generateContent(prompt: String, history: [[String: Any]] = []) async throws -> GeminiResponse {
        guard let url = URL(string: baseURL) else {
            throw GeminiAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var contents: [[String: Any]] = []
        contents.append(contentsOf: history)
        contents.append(["role": "user", "parts": [["text": prompt]]])

        let requestBody: [String: Any] = [
            "contents": contents,
            "tools": [
                [
                    "functionDeclarations": [
                        [
                            "name": "execute_shell_command",
                            "description": "Executes a shell command on the user's machine and returns the output.",
                            "parameters": [
                                "type": "object",
                                "properties": [
                                    "command": [
                                        "type": "string",
                                        "description": "The shell command to execute."
                                    ]
                                ],
                                "required": ["command"]
                            ]
                        ]
                    ]
                ]
            ]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            throw GeminiAPIError.decodingError
        }

        request.httpBody = jsonData

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiAPIError.unknown
        }

        if httpResponse.statusCode != 200 {
            let errorString = String(data: data, encoding: .utf8) ?? "Unknown API Error"
            throw GeminiAPIError.apiError("API Error: Status \(httpResponse.statusCode), \(errorString)")
        }

        guard let jsonResponse = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            throw GeminiAPIError.decodingError
        }

        // Parse the response for text or tool calls
        if let candidates = jsonResponse["candidates"] as? [[String: Any]],
           let firstCandidate = candidates.first,
           let content = firstCandidate["content"] as? [String: Any],
           let parts = content["parts"] as? [[String: Any]],
           let firstPart = parts.first {

            if let text = firstPart["text"] as? String {
                return .text(text)
            } else if let functionCall = firstPart["functionCall"] as? [String: Any],
                      let name = functionCall["name"] as? String,
                      let args = functionCall["args"] as? [String: Any] {
                return .toolCall(name: name, args: args)
            }
        }
        throw GeminiAPIError.decodingError
    }
}
