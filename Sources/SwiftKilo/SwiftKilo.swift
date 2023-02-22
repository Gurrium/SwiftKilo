import Foundation

@main
public struct SwiftKilo {
    public static func main() {
        enableRawMode()

        var char: UInt8 = 0
        while read(FileHandle.standardInput.fileDescriptor, &char, 1) == 1,
              let parsed = String(bytes: [char], encoding: .utf8),
              parsed != "q" {
            print(parsed)
        }
    }

    private static func enableRawMode() {
        var raw = termios()
        tcgetattr(STDIN_FILENO, &raw)

        raw.c_lflag &= tcflag_t(truncatingIfNeeded: ~(ECHO))

        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
    }
}
