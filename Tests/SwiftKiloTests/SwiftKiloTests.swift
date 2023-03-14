import XCTest
import System
@testable import SwiftKilo

final class SwiftKiloTests: XCTestCase {
    func testExample() async throws {
        let (inHandle, outHandle): (FileHandle, FileHandle) = {
            let pipe = Pipe()
            return (pipe.fileHandleForWriting, pipe.fileHandleForReading)
        }()

        Task.detached {
            try await Task.sleep(nanoseconds: 1_000_000)
            try inHandle.write(contentsOf: [0])
            try inHandle.write(contentsOf: [1])
            try inHandle.write(contentsOf: [2])
            try inHandle.write(contentsOf: [3])
        }

        let testTask = Task {
            var bytes = [UInt8]()
            
            for try await byte in outHandle.bytes {
                bytes.append(byte)
                
                if bytes == [0, 1, 2, 3] {
                    break
                }
            }
        }

        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: 5_000_000)
            testTask.cancel()
        }

        do {
            _ = try await testTask.value
            timeoutTask.cancel()
        } catch {
            XCTFail("timeout")
        }
    }
}
