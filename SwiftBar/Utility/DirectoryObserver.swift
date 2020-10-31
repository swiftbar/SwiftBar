import Foundation

class DirectoryObserver {
    private let fileDescriptor: CInt
    private let source: DispatchSourceProtocol

    deinit {

        self.source.cancel()
        close(fileDescriptor)
    }

    init(URL: URL, block: @escaping ()->Void) {
        self.fileDescriptor = open(URL.path, O_EVTONLY)
        self.source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: self.fileDescriptor, eventMask: .all, queue: DispatchQueue.global())
        self.source.setEventHandler {
            block()
        }
        self.source.resume()
    }
}

