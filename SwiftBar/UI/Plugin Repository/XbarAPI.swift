import Combine
import Foundation

struct Agent {
    let session = URLSession.shared

    struct Response<T> {
        let value: T
        let response: URLResponse
    }

    func run<T: Decodable>(_ request: URLRequest, _ decoder: JSONDecoder = JSONDecoder()) -> AnyPublisher<Response<T>, Error> {
        let cache = URLCache.shared
        if request.cachePolicy != .reloadIgnoringCacheData, let cachedResponse = cache.cachedResponse(for: request) {
            return Just(cachedResponse)
                .tryMap { result -> Response<T> in
                    let value = try decoder.decode(T.self, from: result.data)
                    return Response(value: value, response: result.response)
                }
                .receive(on: DispatchQueue.main)
                .eraseToAnyPublisher()
        }

        return URLSession.shared
            .dataTaskPublisher(for: request)
            .tryMap { result -> Response<T> in
                let value = try decoder.decode(T.self, from: result.data)
                let cachedData = CachedURLResponse(response: result.response, data: result.data)
                cache.storeCachedResponse(cachedData, for: request)
                return Response(value: value, response: result.response)
            }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
}

enum XbarAPI {
    static let agent = Agent()
    static let base = URL(string: "https://xbarapp.com/docs/plugins/")!
}

extension XbarAPI {
    static func categories(ignoreCache: Bool = false) -> AnyPublisher<RepositoryCategory, Error> {
        run(URLRequest(url: base.appendingPathComponent("categories.json"),
                       cachePolicy: ignoreCache ? .reloadIgnoringCacheData : .returnCacheDataElseLoad))
    }

    static func plugins(category: String, ignoreCache: Bool = false) -> AnyPublisher<RepositoryPlugin, Error> {
        run(URLRequest(url: base.appendingPathComponent("\(category)/plugins.json"),
                       cachePolicy: ignoreCache ? .reloadIgnoringCacheData : .returnCacheDataElseLoad))
    }

    static func run<T: Decodable>(_ request: URLRequest) -> AnyPublisher<T, Error> {
        agent.run(request)
            .map(\.value)
            .eraseToAnyPublisher()
    }
}
