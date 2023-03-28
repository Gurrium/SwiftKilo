import Foundation

// TODO: printではなくfileHandle.fileDescriptor.writeを使う

@main
public class SwiftKilo {
    struct EditorConfig {
        var origTermios: termios
        var screenRows: Int
        var screenCols: Int
    }

    public static func main() async throws {
        try await SwiftKilo()?.main()
    }

    private let fileHandle: FileHandle
    private var editorConfig: EditorConfig!

    init?(fileHandle: FileHandle = .standardInput) {
        self.fileHandle = fileHandle

        guard let (height, width) = getWindowSize() else { return nil }

        editorConfig = EditorConfig(
            origTermios: .init(),
            screenRows: height,
            screenCols: width
        )
    }

    deinit {
        disableRawMode()
    }

    private func main() async throws {
        enableRawMode()

        // TODO: 一定間隔でUnicodeScalar?を返すAsyncSequenceにする
        for try await scalar in fileHandle.bytes.unicodeScalars {
            refreshScreen()

            if process(scalar) {
                print("\u{1b}[2J")
                print("\u{1b}[H")

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

        try? fileHandle.write(contentsOf: Array("\u{1b}[H".utf8))
    }

    private func drawRows() {
        (0..<editorConfig.screenRows).forEach { _ in
            print("~\r\n")
        }
    }

    private func getWindowSize() -> (height: Int, width: Int)? {
        var windowSize = winsize()

        guard ioctl(fileHandle.fileDescriptor, TIOCGWINSZ, &windowSize) != -1 else {
            return nil
        }

        return (height: Int(windowSize.ws_row), width: Int(windowSize.ws_col))
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
