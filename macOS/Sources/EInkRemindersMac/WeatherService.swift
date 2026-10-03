import Foundation

/// Fetches temperature on the Mac; the NOTE4 only receives a one-bit text patch.
/// MET Norway is an independent fallback when Open-Meteo cannot be reached.
struct WeatherService: Sendable {
    private let fetch: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    init(session: URLSession = .shared) {
        fetch = { request in try await session.data(for: request) }
    }

    init(fetch: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)) {
        self.fetch = fetch
    }

    func currentCelsius(latitude: Double, longitude: Double) async throws -> Double {
        do {
            return try await openMeteoCelsius(latitude: latitude, longitude: longitude)
        } catch {
            // A cancelled sync must not start another network request.
            try Task.checkCancellation()
            return try await metNorwayCelsius(latitude: latitude, longitude: longitude)
        }
    }

    private func openMeteoCelsius(latitude: Double, longitude: Double) async throws -> Double {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m"),
            URLQueryItem(name: "forecast_days", value: "1")
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 10
        let (data, response) = try await fetch(request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw WeatherError.badResponse
        }
        let result = try JSONDecoder().decode(Forecast.self, from: data)
        return try validated(result.current.temperature_2m)
    }

    private func metNorwayCelsius(latitude: Double, longitude: Double) async throws -> Double {
        var components = URLComponents(string: "https://api.met.no/weatherapi/locationforecast/2.0/compact")!
        // MET Norway rejects coordinates with more than four decimal places.
        components.queryItems = [
            URLQueryItem(name: "lat", value: String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), latitude)),
            URLQueryItem(name: "lon", value: String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), longitude))
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 10
        request.setValue(
            "EInkReminders/1.1 (+https://github.com/wegooo-cell/EInkReminders)",
            forHTTPHeaderField: "User-Agent"
        )
        let (data, response) = try await fetch(request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw WeatherError.badResponse
        }
        let result = try JSONDecoder().decode(LocationForecast.self, from: data)
        guard let first = result.properties.timeseries.first else {
            throw WeatherError.badResponse
        }
        return try validated(first.data.instant.details.air_temperature)
    }

    private func validated(_ temperature: Double) throws -> Double {
        guard temperature.isFinite, (-100...70).contains(temperature) else {
            throw WeatherError.badResponse
        }
        return temperature
    }

    private struct Forecast: Decodable {
        struct Current: Decodable { let temperature_2m: Double }
        let current: Current
    }

    private struct LocationForecast: Decodable {
        struct Properties: Decodable {
            struct TimeStep: Decodable {
                struct DataPoint: Decodable {
                    struct Instant: Decodable {
                        struct Details: Decodable { let air_temperature: Double }
                        let details: Details
                    }
                    let instant: Instant
                }
                let data: DataPoint
            }
            let timeseries: [TimeStep]
        }
        let properties: Properties
    }

    enum WeatherError: Error { case badResponse }
}
