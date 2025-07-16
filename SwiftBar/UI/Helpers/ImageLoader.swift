import Cocoa
import Combine
import Foundation

class ImageLoader: ObservableObject {
    @Published var imageData = NSImage(named: "AppIcon")!.tiffRepresentation

    init(url: URL) {
        let cache = URLCache.shared
        let request = URLRequest(url: url, cachePolicy: URLRequest.CachePolicy.returnCacheDataElseLoad, timeoutInterval: 60.0)
        if let data = cache.cachedResponse(for: request)?.data {
            imageData = data
        } else {
            URLSession.shared.dataTask(with: request, completionHandler: { data, response, _ in
                if let data, let response {
                    let cachedData = CachedURLResponse(response: response, data: data)
                    cache.storeCachedResponse(cachedData, for: request)
                    DispatchQueue.main.async {
                        self.imageData = data
                    }
                }
            }).resume()
        }
    }
}
