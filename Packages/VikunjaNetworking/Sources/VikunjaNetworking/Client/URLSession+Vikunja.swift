import Foundation

public extension URLSession {
    /// Default transport for every Vikunja API call. Apple's plain `.shared`
    /// session leaves a 60s request timeout and a 7-day resource timeout in
    /// place, generous enough to let a stalled self-hosted instance hang an
    /// interactive screen far longer than it should. 15s/60s give a slow
    /// home-server connection room to breathe without leaving the UI
    /// spinning indefinitely; `Endpoint.timeoutInterval` extends this further
    /// for attachment transfers specifically.
    static let vikunjaDefault: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 60
        return URLSession(configuration: configuration)
    }()
}
