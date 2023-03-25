import Foundation

@main
public class SwiftKilo {
    struct EditorConfig {
        var origTermios: termios
    }

    private var editorConfig: EditorConfig

    public static func main() async throws {
        try await SwiftKilo().main()
    }

    init() {
        editorConfig = EditorConfig(origTermios: .init())
    }

    deinit {
        disableRawMode()
    }

    private func main() async throws {
        enableRawMode()

        // TODO: 一定間隔でUnicodeScalar?を返すAsyncSequenceにする
        for try await scalar in FileHandle.standardInput.bytes.unicodeScalars {
            refreshScreen()

            if process(scalar) {
                refreshScreen()
                break
            }
        }
    }

    // MARK: key processing

    // TODO: そのうち分岐が増えたらenumを返すようにする
    private func process(_ scalar: UnicodeScalar) -> Bool {
        return scalar.isControlKeyEquivalent(to: "q")
    }

    // MARK: rendering

    private func refreshScreen() {
        print("\u{1b}[2J")
        print("\u{1b}[H")

        drawRows()

        print("\u{1b}[H")
    }

    private func drawRows() {
        (0..<24).forEach { _ in
            print("~\r")
        }
    }

    private func enableRawMode() {
        tcgetattr(STDIN_FILENO, &editorConfig.origTermios)

        var new = editorConfig.origTermios
        new.c_iflag &= ~tcflag_t(BRKINT | ICRNL | INPCK | ISTRIP | IXON)
        new.c_oflag &= ~tcflag_t(OPOST)
        new.c_cflag |= tcflag_t(CS8)
        new.c_lflag &= ~tcflag_t(ECHO | ICANON | IEXTEN | ISIG)

        tcsetattr(STDIN_FILENO, TCSAFLUSH, &new)
    }

    private func disableRawMode() {
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &editorConfig.origTermios)
    }
}

extension UnicodeScalar {
    func isControlKeyEquivalent(to character: Character) -> Bool {
        guard isASCII,
              let asciiValue = character.asciiValue else { return false }

        return self.value == UInt32(asciiValue & 0b00011111)
    }
}
