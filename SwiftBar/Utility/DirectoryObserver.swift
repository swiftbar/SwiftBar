import Foundation

class DirectoryObserver {
    private let fileDescriptor: CInt
    private let source: DispatchSourceProtocol
    public let url: URL

    deinit {
        self.source.cancel()
        close(fileDescriptor)
    }

    init(url: URL, block: @escaping ()->Void) {
        self.url = url
        self.fileDescriptor = open(url.path, O_EVTONLY)
        self.source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: self.fileDescriptor, eventMask: .all, queue: DispatchQueue.global())
        self.source.setEventHandler {
            block()
        }
        self.source.resume()
    }
}

