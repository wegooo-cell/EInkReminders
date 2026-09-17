import Foundation

enum DeviceDisplayState: String, Sendable {
    case normal
    case idle
    case confirmation = "confirm"
}

struct DeviceClient: Sendable {
    let baseURL: URL
    var session: URLSession = .shared

    func status() async throws -> DeviceStatus {
        try await get("api/status")
    }

    func operations(after sequence: UInt64) async throws -> [DeviceOperation] {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/operations"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "after", value: String(sequence))]

        // 与 get 相同，读接口缩短超时，设备离线时尽快失败。
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 10

        let (data, response) = try await session.data(for: request)
        try validate(response, data: data, endpoint: "/api/operations")
        return try WireCoding.decoder().decode(DeviceOperationsResponse.self, from: data).operations
    }

    func send(snapshot: DeviceSnapshot) async throws {
        try await postJSON(snapshot, path: "api/snapshot")
    }

    func send(
        display: Data,
        index: Int,
        state: DeviceDisplayState = .normal
    ) async throws {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/display"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "index", value: String(index)),
            URLQueryItem(name: "state", value: state.rawValue)
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue(String(index), forHTTPHeaderField: "X-Page-Index")
        request.timeoutInterval = 20
        let (data, response) = try await session.upload(for: request, from: display)
        try validate(response, data: data, endpoint: "/api/display?index=\(index)&state=\(state.rawValue)")
    }

    func acknowledge(through sequence: UInt64) async throws {
        try await postJSON(["through": sequence], path: "api/operations/ack")
    }

    func acknowledgeSyncRequest() async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/sync/ack"))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data, endpoint: "/api/sync/ack")
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))

        // 读接口不用默认的 60 秒超时，设备离线时每秒一次的轮询要尽快失败。
        // 设备处理画面上传时会同步刷新墨水屏，读请求可能排队数秒，10 秒足够覆盖。
        request.timeoutInterval = 10

        let (data, response) = try await session.data(for: request)
        try validate(response, data: data, endpoint: "/\(path)")
        return try WireCoding.decoder().decode(T.self, from: data)
    }

    private func postJSON<T: Encodable>(_ value: T, path: String) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try WireCoding.encoder().encode(value)
        request.timeoutInterval = 20
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data, endpoint: "/\(path)")
    }

    private func validate(_ response: URLResponse, data: Data, endpoint: String) throws {
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            let detail = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ClientError.badResponse(endpoint, (response as? HTTPURLResponse)?.statusCode, detail)
        }
    }

    enum ClientError: LocalizedError {
        case badResponse(String, Int?, String?)
        var errorDescription: String? {
            switch self {
            case .badResponse(let endpoint, let code, let detail):
                let suffix = detail.flatMap { $0.isEmpty ? nil : " · \($0)" } ?? ""
                return "设备响应异常：\(endpoint) · HTTP \(code.map(String.init) ?? "未知")\(suffix)"
            }
        }
    }
}
