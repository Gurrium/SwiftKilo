import Foundation
import AsyncAlgorithms
import System

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
        private(set) var x: Int
        private(set) var y: Int

        enum Direction {
            case up
            case down
            case left
            case right
        }

        mutating func move(_ direction: Direction, limit: Int) {
            switch direction {
            case .up:
                y = max(limit, y - 1)
            case .down:
                y = min(limit, y + 1)
            case .left:
                x = max(limit, x - 1)
            case .right:
                x = min(limit, x + 1)
            }
        }
    }

    struct EditorConfig {
        var cursorPosition: CursorPosition
        var screenRows: Int
        var screenCols: Int
        var origTermios: termios
        var rows: [String]
        var rowOffset: Int
        var columnOffset: Int
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
            cursorPosition: CursorPosition(x: 0, y: 0),
            screenRows: height,
            screenCols: width,
            origTermios: .init(),
            rows: [],
            rowOffset: 0,
            columnOffset: 0
        )
    }

    deinit {
        disableRawMode()
    }

    private func main() async throws {
        enableRawMode()

        let args = CommandLine.arguments
        try openEditor(filePath: args.count > 1 ? args[1] : nil)

        for try await scalar in merge(fileHandle.bytes.unicodeScalars.map({ (element: AsyncUnicodeScalarSequence<FileHandle.AsyncBytes>.Element) -> AsyncUnicodeScalarSequence<FileHandle.AsyncBytes>.Element? in element }), Interval(value: nil)) {
            refreshScreen()

            if let scalar,
               let action = keyProcessor.process(scalar) {
                switch action {
                // cursor
                case .moveCursorUp:
                    editorConfig.cursorPosition.move(.up, limit: 0)
                case .moveCursorLeft:
                    editorConfig.cursorPosition.move(.left, limit: 0)
                case .moveCursorRight:
                    editorConfig.cursorPosition.move(.right, limit: editorConfig.rows[editorConfig.cursorPosition.y].count)
                case .moveCursorDown:
                    editorConfig.cursorPosition.move(.down, limit: editorConfig.rows.count)
                case .moveCursorToBeginningOfLine:
                    for _ in 0..<editorConfig.screenCols {
                        editorConfig.cursorPosition.move(.left, limit: 0)
                    }
                case .moveCursorToEndOfLine:
                    for _ in 0..<editorConfig.screenCols {
                        editorConfig.cursorPosition.move(.right, limit: editorConfig.screenCols)
                    }
                // page
                case .movePageUp:
                    for _ in 0..<editorConfig.screenRows {
                        editorConfig.cursorPosition.move(.up, limit: 0)
                    }
                case .movePageDown:
                    for _ in 0..<editorConfig.screenRows {
                        editorConfig.cursorPosition.move(.down, limit: editorConfig.rows.count)
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

    private func openEditor(filePath: String?) throws {
        let rows: [String]
        if let filePath,
           let data = FileManager.default.contents(atPath: filePath),
           let contents = String(data: data, encoding: .utf8) {
            rows = contents.split(whereSeparator: \.isNewline).map { String($0) }
        } else {
            rows = []
        }

        editorConfig.rows = rows
    }

    // MARK: rendering

    private func scroll() {
        if editorConfig.cursorPosition.y < editorConfig.rowOffset {
            editorConfig.rowOffset = editorConfig.cursorPosition.y
        }

        if editorConfig.cursorPosition.y >= editorConfig.rowOffset + editorConfig.screenRows {
            editorConfig.rowOffset = editorConfig.cursorPosition.y - editorConfig.screenRows + 1
        }

        if editorConfig.cursorPosition.x < editorConfig.columnOffset {
            editorConfig.columnOffset = editorConfig.cursorPosition.x
        }

        if editorConfig.cursorPosition.x >= editorConfig.columnOffset + editorConfig.screenCols {
            editorConfig.columnOffset = editorConfig.cursorPosition.x - editorConfig.screenCols + 1
        }
    }

    private func refreshScreen() {
        scroll()

        buffer = ""

        buffer.append("\u{1b}[?25l")
        buffer.append("\u{1b}[H")

        drawRows()

        buffer.append("\u{1b}[\(editorConfig.cursorPosition.y - editorConfig.rowOffset + 1);\((editorConfig.cursorPosition.x - editorConfig.columnOffset) + 1)H")

        buffer.append("\u{1b}[?25h")

        fileHandle.print(buffer)
    }

    private func drawRows() {
        for y in (0..<editorConfig.screenRows) {
            let fileRow = y + editorConfig.rowOffset

            if (fileRow >= editorConfig.rows.count) {
                if editorConfig.rows.count == 0 && y == editorConfig.screenRows / 3 {
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
                buffer.append(String(editorConfig.rows[fileRow].dropFirst(editorConfig.columnOffset).prefix(editorConfig.screenCols)))
            }

            buffer.append("\u{1b}[K")
            if y < editorConfig.screenRows - 1 {
                buffer.append("\r\n")
            }
        }
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
