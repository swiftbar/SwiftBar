import Foundation
import Testing

@testable import SwiftBar

private final class OutputRecorder {
    private let lock = NSLock()
    private var values: [String?] = []
    private var writeError: String?

    func append(_ value: String?) -> Bool {
        lock.lock()
        values.append(value)
        let isFirstValue = values.count == 1
        lock.unlock()
        return isFirstValue
    }

    func recordWriteError(_ error: Error) {
        lock.lock()
        writeError = error.localizedDescription
        lock.unlock()
    }

    func recordedValues() -> [String?] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }

    func recordedWriteError() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return writeError
    }
}

struct RunScriptTests {
    @Test func utf8ChunkDecoder_reassemblesScalarsSplitAtEveryByte() {
        let expected = "A¢●🌍Z"
        let bytes = Array(expected.utf8)

        for splitIndex in 0 ... bytes.count {
            var decoder = UTF8ChunkDecoder()
            let first = decoder.decode(Data(bytes[..<splitIndex]))
            let second = decoder.decode(Data(bytes[splitIndex...]))

            #expect(first + second + decoder.finish() == expected)
        }

        var byteAtATimeDecoder = UTF8ChunkDecoder()
        let byteAtATime = bytes
            .map { byteAtATimeDecoder.decode(Data([$0])) }
            .joined()
        #expect(byteAtATime + byteAtATimeDecoder.finish() == expected)
    }

    @Test func utf8ChunkDecoder_replacesIncompleteScalarAtEndOfStream() {
        var decoder = UTF8ChunkDecoder()

        #expect(decoder.decode(Data([0xE2, 0x97])).isEmpty)
        #expect(decoder.finish() == "�")
        #expect(decoder.finish().isEmpty)
    }

    @Test func runScript_streamOutputPreservesUTF8SplitAcrossPipeReads() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let scriptURL = tempDirectory.appendingPathComponent("split-utf8.sh")
        let script = """
        #!/bin/sh
        printf 'prefix \\342\\227'
        read _
        printf '\\217 suffix\\n'
        """
        try Data(script.utf8).write(to: scriptURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let recorder = OutputRecorder()
        let stdinPipe = Pipe()
        let result = try runScript(
            to: scriptURL.path,
            runInBash: false,
            streamOutput: true,
            stdinPipe: stdinPipe,
            onOutputUpdate: { value in
                if recorder.append(value) {
                    do {
                        try stdinPipe.fileHandleForWriting.write(contentsOf: Data("\n".utf8))
                    } catch {
                        recorder.recordWriteError(error)
                    }
                }
            }
        )
        let updates = recorder.recordedValues()

        #expect(recorder.recordedWriteError() == nil)
        #expect(updates.allSatisfy { $0 != nil })
        #expect(updates.compactMap { $0 }.joined() == "prefix ● suffix\n")
        #expect(result.out == "prefix ● suffix\n")
    }
}
