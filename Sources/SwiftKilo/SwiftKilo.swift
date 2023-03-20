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
           if CharacterSet.controlCharacters.contains(scalar) {
                print("\(scalar.value)\r")
            } else {
                print("\(scalar.value) ('\(scalar)')\r")
            }

            if scalar.isControlKeyEquivalent(to: "q") {
                break
            }
        }
    }

    private func enableRawMode() {
        tcgetattr(STDIN_FILENO, &origTermios)

        var new = origTermios
        new.c_iflag &= ~tcflag_t(BRKINT | ICRNL | INPCK | ISTRIP | IXON)
        new.c_oflag &= ~tcflag_t(OPOST)
        new.c_cflag |= tcflag_t(CS8)
        new.c_lflag &= ~tcflag_t(ECHO | ICANON | IEXTEN | ISIG)

        tcsetattr(STDIN_FILENO, TCSAFLUSH, &new)
    }

    private func disableRawMode() {
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &origTermios)
    }
}

extension UnicodeScalar {
    func isControlKeyEquivalent(to character: Character) -> Bool {
        guard isASCII,
              let asciiValue = character.asciiValue else { return false }

        return self.value == UInt32(asciiValue & 0b00011111)
    }
}
