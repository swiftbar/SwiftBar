import Foundation

#if !MAC_APP_STORE

    struct DirectoryObserverError: LocalizedError {
        let url: URL
        let errorCode: CInt

        var errorDescription: String? {
            "Failed to open directory \(url.path): \(String(cString: strerror(errorCode))) (\(errorCode))"
        }
    }

    final class DirectoryObserver {
        private let source: DispatchSourceProtocol
        public let url: URL

        deinit {
            source.cancel()
        }

        init(url: URL, block: @escaping () -> Void) throws {
            let fileDescriptor = open(url.path, O_EVTONLY)
            guard fileDescriptor >= 0 else {
                throw DirectoryObserverError(url: url, errorCode: errno)
            }

            self.url = url
            source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fileDescriptor, eventMask: .all, queue: DispatchQueue.global())
            source.setEventHandler {
                block()
            }
            source.setCancelHandler {
                close(fileDescriptor)
            }
            source.resume()
        }
    }
#endif
