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
        let maxX: Int
        let maxY: Int

        private(set) var x: Int
        private(set) var y: Int

        enum Direction {
            case up
            case down
            case left
            case right
        }

        mutating func move(_ direction: Direction) {
            switch direction {
            case .up:
                y = max(0, y - 1)
            case .down:
                y = min(maxY, y + 1)
            case .left:
                x = max(0, x - 1)
            case .right:
                x = min(maxX, x + 1)
            }
        }
    }

    struct EditorConfig {
        var cursorPosition: CursorPosition
        var screenRows: Int
        var screenCols: Int
        var origTermios: termios
        var rows: [String]
    }

    public static func main() async throws {
        try await SwiftKilo()?.main()
    }

    private let fileHandle: FileHandle
    private var editorConfig: EditorConfig!
    private var buffer = ""
    private var keyProcessor = KeyProcessor()

    init?(fileHandle: FileHandle = .standardInput) {
        self.fileHandle = fileHandle

        guard let (height, width) = getWindowSize() else { return nil }

        editorConfig = EditorConfig(
            cursorPosition: CursorPosition(maxX: width - 1, maxY: height - 1, x: 0, y: 0),
            screenRows: height,
            screenCols: width,
            origTermios: .init(),
            rows: []
        )
    }

    deinit {
        disableRawMode()
    }

    private func main() async throws {
        enableRawMode()
        openEditor()

        for try await scalar in merge(fileHandle.bytes.unicodeScalars.map({ (element: AsyncUnicodeScalarSequence<FileHandle.AsyncBytes>.Element) -> AsyncUnicodeScalarSequence<FileHandle.AsyncBytes>.Element? in element }), Interval(value: nil)) {
            refreshScreen()

            if let scalar,
               let action = keyProcessor.process(scalar) {
                switch action {
                // cursor
                case .moveCursorUp:
                    editorConfig.cursorPosition.move(.up)
                case .moveCursorLeft:
                    editorConfig.cursorPosition.move(.left)
                case .moveCursorRight:
                    editorConfig.cursorPosition.move(.right)
                case .moveCursorDown:
                    editorConfig.cursorPosition.move(.down)
                case .moveCursorToBeginningOfLine:
                    for _ in 0..<editorConfig.screenCols {
                        editorConfig.cursorPosition.move(.left)
                    }
                case .moveCursorToEndOfLine:
                    for _ in 0..<editorConfig.screenCols {
                        editorConfig.cursorPosition.move(.right)
                    }
                // page
                case .movePageUp:
                    for _ in 0..<editorConfig.screenRows {
                        editorConfig.cursorPosition.move(.up)
                    }
                case .movePageDown:
                    for _ in 0..<editorConfig.screenRows {
                        editorConfig.cursorPosition.move(.down)
                    }
                // text
                case .delete:
                    // TODO: impl
                    break
                case .quit:
                    fileHandle.print("\u{1b}[2J")
                    fileHandle.print("\u{1b}[H")

                    return
                }
            }
        }
    }

    // MARK: file i/o

    private func openEditor() {
        editorConfig.rows = ["Hello, world!"]
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
        for y in (0..<(editorConfig.screenRows - 1)) {
            if (y >= editorConfig.rows.count) {
                if y == editorConfig.screenRows / 3 {
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
            } else {
                buffer.append(String(editorConfig.rows[y].prefix(editorConfig.screenCols)))
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

    func modified(with modifierKeys: Modifier...) -> UnicodeScalar {
        guard isASCII else { preconditionFailure("self(\(self)) must be ASCII") }

        let modified = modifierKeys.reduce(value) { partialResult, modifier in value & modifier.mask }

        return UnicodeScalar(modified)!
    }

    enum Modifier {
        case control

        var mask: UInt32 {
            switch self {
            case .control:
                return 0b0001_1111
            }
        }
    }
}

enum EditorAction {
    // MARK: cursor
    case moveCursorUp
    case moveCursorLeft
    case moveCursorRight
    case moveCursorDown
    case moveCursorToEndOfLine
    case moveCursorToBeginningOfLine

    // MARK: page
    case movePageUp
    case movePageDown

    // MARK: text
    case delete

    // MARK: editor
    case quit
}
