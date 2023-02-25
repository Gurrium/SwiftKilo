import Foundation

@main
public class SwiftKilo {
    public static func main() {
        SwiftKilo().main()
    }

    private var origTermios: termios

    init() {
        origTermios = termios()
    }

    deinit {
        disableRawMode()
    }

    private func main() {
        enableRawMode()

        var char: UInt8 = 0
        while read(FileHandle.standardInput.fileDescriptor, &char, 1) == 1,
              let parsed = String(bytes: [char], encoding: .utf8),
              parsed != "q" {
            print(parsed)
        }
    }

    private func enableRawMode() {
        tcgetattr(STDIN_FILENO, &origTermios)

        var new = origTermios
        new.c_lflag &= ~tcflag_t(ECHO)

        tcsetattr(STDIN_FILENO, TCSAFLUSH, &new)
    }

    private func disableRawMode() {
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &origTermios)
    }
}
