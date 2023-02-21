import Foundation

@main
public struct SwiftKilo {
    public static func main() {
        var char: UInt8 = 0
        while read(FileHandle.standardInput.fileDescriptor, &char, 1) == 1,
              let parsed = String(bytes: [char], encoding: .utf8),
              parsed != "q" {
            print(parsed)
        }
    }
}
