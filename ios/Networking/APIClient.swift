import Foundation

/// Shared API client — ALL network calls go through this singleton.
/// Views never call URLSession directly.
actor APIClient {
    static let shared = APIClient()

    // FILL IN: Your API base URL
    private let baseURL = ""

    private func authHeaders() -> [String: String] {
        // FILL IN: Return auth headers
        [:]
    }

    func get<T: Decodable>(_ endpoint: String, params: [String: String] = [:]) async throws -> T {
        var components = URLComponents(string: baseURL + endpoint)!
        components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!)
        for (k, v) in authHeaders() { request.setValue(v, forHTTPHeaderField: k) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200...299 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func post<T: Decodable>(_ endpoint: String, body: Encodable) async throws -> T {
        var request = URLRequest(url: URL(string: baseURL + endpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in authHeaders() { request.setValue(v, forHTTPHeaderField: k) }
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200...299 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
