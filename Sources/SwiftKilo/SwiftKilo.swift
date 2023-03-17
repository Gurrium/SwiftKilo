import Foundation

@main
public class SwiftKilo {
    public static func main() async throws {
        try await SwiftKilo().main()
    }

    private var origTermios: termios

    init() {
        origTermios = termios()
    }

    deinit {
        disableRawMode()
    }

    private func main() async throws {
        enableRawMode()

        for try await scalar in FileHandle.standardInput.bytes.unicodeScalars {
            guard scalar != "q" else { break }

            if CharacterSet.controlCharacters.contains(scalar) {
                print("\(scalar.value)")
            } else {
                print("\(scalar.value) ('\(scalar)')")
            }
        }
    }

    private func enableRawMode() {
        tcgetattr(STDIN_FILENO, &origTermios)

        var new = origTermios
        new.c_iflag &= ~tcflag_t(IXON)
        new.c_lflag &= ~tcflag_t(ECHO | ICANON | ISIG)

        tcsetattr(STDIN_FILENO, TCSAFLUSH, &new)
    }

    private func disableRawMode() {
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &origTermios)
    }
}
