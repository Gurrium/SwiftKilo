import Foundation
import AsyncAlgorithms

let versionString = "0.1"

struct Interval<Value>: AsyncSequence {
    typealias AsyncIterator = Iterator
    typealias Element = Value

    let value: Value

    func makeAsyncIterator() -> Iterator {
        Iterator(value: value)
    }

    struct Iterator: AsyncIteratorProtocol {
        let value: Value

        func next() async throws -> Element? {
            try await Task.sleep(nanoseconds: 10_000_000)

            return value
        }
    }
}

@main
public class SwiftKilo {
    struct CursorPosition {
        var x: Int
        var y: Int

        enum Direction {
            case up
            case down
            case left
            case right
        }

        mutating func move(_ direction: Direction) {
            switch direction {
            case .up:
                y -= 1
            case .down:
                y += 1
            case .left:
                x -= 1
            case .right:
                x += 1
            }
        }
    }

    struct EditorConfig {
        var cursorPosition: CursorPosition
        var screenRows: Int
        var screenCols: Int
        var origTermios: termios
    }

    public static func main() async throws {
        try await SwiftKilo()?.main()
    }

    private let fileHandle: FileHandle
    private var editorConfig: EditorConfig!
    private var buffer = ""

    init?(fileHandle: FileHandle = .standardInput) {
        self.fileHandle = fileHandle

        guard let (height, width) = getWindowSize() else { return nil }

        editorConfig = EditorConfig(
            cursorPosition: CursorPosition(x: 0, y: 0),
            screenRows: height,
            screenCols: width,
            origTermios: .init()
        )
    }

    deinit {
        disableRawMode()
    }

    private func main() async throws {
        enableRawMode()

        for try await scalar in merge(fileHandle.bytes.unicodeScalars.map({ (element: AsyncUnicodeScalarSequence<FileHandle.AsyncBytes>.Element) -> AsyncUnicodeScalarSequence<FileHandle.AsyncBytes>.Element? in element }), Interval(value: nil)) {
            refreshScreen()

            if let scalar,
               process(scalar) {
                fileHandle.print("\u{1b}[2J")
                fileHandle.print("\u{1b}[H")

                break
            }
        }
    }

    // MARK: key processing

    // TODO: そのうち分岐が増えたらenumを返すようにする
    private func process(_ scalar: UnicodeScalar) -> Bool {
        if scalar.isControlKeyEquivalent(to: "q") {
            return true
        }

        switch scalar {
        case "h":
            editorConfig.cursorPosition.move(.left)
        case "j":
            editorConfig.cursorPosition.move(.down)
        case "k":
            editorConfig.cursorPosition.move(.up)
        case "l":
            editorConfig.cursorPosition.move(.right)
        default:
            break
        }

        return false
    }

    // MARK: rendering

    private func refreshScreen() {
        buffer = ""

        buffer.append("\u{1b}[?25l")
        buffer.append("\u{1b}[H")

        drawRows()

        buffer.append("\u{1b}[\(editorConfig.cursorPosition.y + 1);\(editorConfig.cursorPosition.x + 1)H")

        buffer.append("\u{1b}[?25h")

        fileHandle.print(buffer)
    }

    private func drawRows() {
        for i in (0..<(editorConfig.screenRows - 1)) {
            if i == editorConfig.screenRows / 3 {
                var message = String("SwiftKilo editor -- version \(versionString)".prefix(editorConfig.screenCols))

                var padding = (editorConfig.screenCols - message.count) / 2
                if padding > 0 {
                    buffer.append("~")
                    padding -= 1
                }

                message = "\(Array(repeating: " ", count: padding).joined())\(message)"

                buffer.append(message)
            } else {
                buffer.append(("~"))
            }

            buffer.append("\u{1b}[K\r\n")
        }
        buffer.append("~")
    }

    private func getWindowSize() -> (height: Int, width: Int)? {
        var windowSize = winsize()

        guard ioctl(fileHandle.fileDescriptor, TIOCGWINSZ, &windowSize) != -1 else { return nil }

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

extension FileHandle {
    func print(_ contents: String) {
        try! write(contentsOf: Array(contents.utf8))
    }
}

extension UnicodeScalar {
    func isControlKeyEquivalent(to character: Character) -> Bool {
        guard isASCII,
              let asciiValue = character.asciiValue else { return false }

        return self.value == UInt32(asciiValue & 0b00011111)
    }
}
