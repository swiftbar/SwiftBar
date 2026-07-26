#if !MAC_APP_STORE
    import Foundation
    import Testing

    @testable import SwiftBar

    struct DirectoryObserverTests {
        @Test func reportsOpenFailureForMissingDirectory() {
            let missingDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

            do {
                _ = try DirectoryObserver(url: missingDirectory, block: {})
                Issue.record("Expected directory observation to fail")
            } catch let error as DirectoryObserverError {
                #expect(error.url == missingDirectory)
                #expect(error.errorCode == ENOENT)
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
        }

        @Test func observesAccessibleDirectory() throws {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            let observer = try DirectoryObserver(url: directory, block: {})

            #expect(observer.url == directory)
        }

        @Test func pluginManagerHandlesDirectoryOpenFailure() {
            let missingDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let manager = TestDirectoryPluginManager(pluginDirectoryURL: missingDirectory)

            manager.configureDirectoryObserver()

            #expect(manager.directoryObserver == nil)
        }
    }
#endif
