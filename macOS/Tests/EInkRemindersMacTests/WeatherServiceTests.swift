import Foundation
import XCTest
@testable import EInkRemindersMac

final class WeatherServiceTests: XCTestCase {
    func testPrimarySuccessDoesNotCallFallback() async throws {
        let calls = WeatherCalls()
        let service = WeatherService { request in
            await calls.record(request)
            guard request.url?.host == "api.open-meteo.com" else {
                throw WeatherService.WeatherError.badResponse
            }
            return response(request, status: 200, json: #"{"current":{"temperature_2m":29.4}}"#)
        }

        let temperature = try await service.currentCelsius(latitude: 23.123456, longitude: 113.123456)
        XCTAssertEqual(temperature, 29.4)
        let requests = await calls.requests
        XCTAssertEqual(requests.count, 1)
    }

    func testFallbackAfterPrimaryFailureUsesIdentifiedRequestAndRoundedCoordinates() async throws {
        let calls = WeatherCalls()
        let service = WeatherService { request in
            await calls.record(request)
            if request.url?.host == "api.open-meteo.com" {
                return response(request, status: 503, json: "{}")
            }
            return response(request, status: 200, json: #"{"properties":{"timeseries":[{"data":{"instant":{"details":{"air_temperature":28.6}}}}]}}"#)
        }

        let temperature = try await service.currentCelsius(latitude: 23.123456, longitude: 113.123456)
        XCTAssertEqual(temperature, 28.6)
        let requests = await calls.requests
        XCTAssertEqual(requests.map { $0.url?.host }, ["api.open-meteo.com", "api.met.no"])
        let fallback = try XCTUnwrap(requests.last)
        XCTAssertTrue(try XCTUnwrap(fallback.value(forHTTPHeaderField: "User-Agent")).contains("github.com/wegooo-cell/EInkReminders"))
        let query = try XCTUnwrap(URLComponents(url: try XCTUnwrap(fallback.url), resolvingAgainstBaseURL: false))
        XCTAssertEqual(query.queryItems?.first(where: { $0.name == "lat" })?.value, "23.1235")
        XCTAssertEqual(query.queryItems?.first(where: { $0.name == "lon" })?.value, "113.1235")
    }

    func testBothProvidersFailWithoutInventingTemperature() async {
        let calls = WeatherCalls()
        let service = WeatherService { request in
            await calls.record(request)
            return response(request, status: 503, json: "{}")
        }

        do {
            _ = try await service.currentCelsius(latitude: 23, longitude: 113)
            XCTFail("Expected both providers to fail")
        } catch {
            let requests = await calls.requests
            XCTAssertEqual(requests.count, 2)
        }
    }
}

private actor WeatherCalls {
    private(set) var requests: [URLRequest] = []
    func record(_ request: URLRequest) { requests.append(request) }
}

private func response(_ request: URLRequest, status: Int, json: String) -> (Data, URLResponse) {
    let url = request.url!
    return (
        Data(json.utf8),
        HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
    )
}
