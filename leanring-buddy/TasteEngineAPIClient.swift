//
//  TasteEngineAPIClient.swift
//  leanring-buddy
//
//  Client for the local Taste Engine service used by Sphere modes.
//

import Foundation

final class TasteEngineAPIClient {
    enum TasteEngineAPIClientError: LocalizedError {
        case invalidBaseURL(String)
        case invalidResponse
        case requestFailed(statusCode: Int, body: String)

        var errorDescription: String? {
            switch self {
            case .invalidBaseURL(let baseURLString):
                return "Invalid Taste Engine base URL: \(baseURLString)"
            case .invalidResponse:
                return "Taste Engine returned an invalid response."
            case .requestFailed(let statusCode, let body):
                if body.isEmpty {
                    return "Taste Engine request failed with status \(statusCode)."
                }
                return "Taste Engine request failed with status \(statusCode): \(body)"
            }
        }
    }

    let baseURL: URL

    private let urlSession: URLSession
    private let jsonEncoder: JSONEncoder
    private let jsonDecoder: JSONDecoder

    init(baseURLString: String, urlSession: URLSession = .shared) throws {
        let trimmedBaseURLString = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseURL = URL(string: trimmedBaseURLString), baseURL.scheme != nil else {
            throw TasteEngineAPIClientError.invalidBaseURL(baseURLString)
        }

        self.baseURL = baseURL
        self.urlSession = urlSession
        self.jsonEncoder = JSONEncoder()
        self.jsonDecoder = JSONDecoder()
        self.jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    func recommend(request: TasteEngineRecommendationRequest) async throws -> TasteEngineAPIResponse {
        return try await postJSON(path: "/api/spheres/recommend", body: request)
    }

    func observe(request: TasteEngineObservationRequest) async throws -> TasteEngineAPIResponse {
        return try await postJSON(path: "/api/spheres/observe", body: request)
    }

    func ingestCapture(request: TasteEngineCaptureIngestRequest) async throws -> TasteEngineAPIResponse {
        return try await postJSON(path: "/api/captures/ingest", body: request)
    }

    func ingestCaptureOrchestrated(request: TasteEngineCaptureIngestRequest) async throws -> TasteEngineAPIResponse {
        return try await postJSON(path: "/api/captures/ingest/orchestrated", body: request)
    }

    func ingestCaptureOrchestrated(request: TasteEngineCaptureIngestRequest) async throws -> TasteEngineAPIResponse {
        return try await postJSON(path: "/api/captures/ingest/orchestrated", body: request)
    }

    func checkStatus() async -> Bool {
        let candidatePaths = ["/api/health", "/"]

        for candidatePath in candidatePaths {
            guard let url = URL(string: candidatePath, relativeTo: baseURL)?.absoluteURL else {
                continue
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 2.0

            do {
                let (_, response) = try await urlSession.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else { continue }
                if (200..<500).contains(httpResponse.statusCode) {
                    return true
                }
            } catch {
                continue
            }
        }

        return false
    }

    private func postJSON<RequestBody: Encodable>(
        path: String,
        body: RequestBody
    ) async throws -> TasteEngineAPIResponse {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw TasteEngineAPIClientError.invalidBaseURL(baseURL.absoluteString)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30.0
        request.httpBody = try jsonEncoder.encode(body)

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TasteEngineAPIClientError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let responseBody = String(data: data, encoding: .utf8) ?? ""
            throw TasteEngineAPIClientError.requestFailed(
                statusCode: httpResponse.statusCode,
                body: responseBody
            )
        }

        if data.isEmpty {
            return try jsonDecoder.decode(TasteEngineAPIResponse.self, from: Data(#"{"summary":"done.","status":"ok"}"#.utf8))
        }

        return try jsonDecoder.decode(TasteEngineAPIResponse.self, from: data)
    }
}
