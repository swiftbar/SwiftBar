import Foundation

class DirectoryObserver {
    private let fileDescriptor: CInt
    private let source: DispatchSourceProtocol
    public let url: URL

    deinit {
        self.source.cancel()
        close(fileDescriptor)
    }

    init(url: URL, block: @escaping () -> Void) {
        self.url = url
        fileDescriptor = open(url.path, O_EVTONLY)
        source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fileDescriptor, eventMask: .all, queue: DispatchQueue.global())
        source.setEventHandler {
            block()
        }
        source.resume()
    }
}
