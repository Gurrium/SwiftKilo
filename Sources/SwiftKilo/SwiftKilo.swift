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
    struct Cursor {
        var x: Int
        var y: Int

        enum Direction {
            case up
            case down
            case left
            case right
        }

        mutating func move(_ direction: Direction, distance: Int) {
            switch direction {
            case .up:
                y = y - distance
            case .down:
                y = y + distance
            case .left:
                x = x - distance
            case .right:
                x = x + distance
            }
        }
    }

    struct File {
        var rows: [String]
        var cursor: Cursor

        var currentRow: String? {
            guard cursor.y < rows.count else { return nil }

            return rows[cursor.y]
        }
    }

    struct Screen {
        let countOfRows: Int
        let countOfColumns: Int

        var rowOffset: Int
        var columnOffset: Int
    }

    struct EditorConfig {
        var screen: Screen
        var origTermios: termios
        var file: File
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
            screen: Screen(countOfRows: height, countOfColumns: width, rowOffset: 0, columnOffset: 0),
            origTermios: termios(),
            file: File(rows: [], cursor: Cursor(x: 0, y: 0))
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
                    guard editorConfig.file.cursor.y > 0 else { break }

                    editorConfig.file.cursor.move(.up, distance: 1)
                case .moveCursorLeft:
                    guard editorConfig.file.cursor.x > 0 else { break }

                    editorConfig.file.cursor.move(.left, distance: 1)
                case .moveCursorRight:
                    guard editorConfig.file.cursor.x < editorConfig.file.currentRow?.count ?? 0 else { break }

                    editorConfig.file.cursor.move(.right, distance: 1)
                case .moveCursorDown:
                    guard editorConfig.file.cursor.y < editorConfig.file.rows.count else { break }

                    editorConfig.file.cursor.move(.down, distance: 1)
                case .moveCursorToBeginningOfLine:
                    editorConfig.file.cursor.x = 0
                case .moveCursorToEndOfLine:
                    editorConfig.file.cursor.x = editorConfig.file.currentRow?.count ?? 0
                // page
                case .movePageUp:
                    editorConfig.file.cursor.move(.up, distance: min(editorConfig.screen.countOfRows, editorConfig.file.cursor.y))
                case .movePageDown:
                    editorConfig.file.cursor.move(.down, distance: min(editorConfig.screen.countOfRows, editorConfig.file.rows.count - editorConfig.file.cursor.y))
                // text
                case .delete:
                    // TODO: impl
                    break
                case .quit:
                    fileHandle.print("\u{1b}[2J")
                    fileHandle.print("\u{1b}[H")

                    return
                }

                if editorConfig.file.cursor.y >= editorConfig.file.rows.count {
                    editorConfig.file.cursor.x = 0
                } else {
                    editorConfig.file.cursor.x = min(editorConfig.file.cursor.x, editorConfig.file.currentRow?.count ?? 0)
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

        editorConfig.file.rows = rows
    }

    // MARK: rendering

    private func scroll() {
        if editorConfig.file.cursor.y < editorConfig.screen.rowOffset {
            editorConfig.screen.rowOffset = editorConfig.file.cursor.y
        }

        if editorConfig.file.cursor.y >= editorConfig.screen.rowOffset + editorConfig.screen.countOfRows {
            editorConfig.screen.rowOffset = editorConfig.file.cursor.y - editorConfig.screen.countOfRows + 1
        }

        if editorConfig.file.cursor.x < editorConfig.screen.columnOffset {
            editorConfig.screen.columnOffset = editorConfig.file.cursor.x
        }

        if editorConfig.file.cursor.x >= editorConfig.screen.columnOffset + editorConfig.screen.countOfColumns {
            editorConfig.screen.columnOffset = editorConfig.file.cursor.x - editorConfig.screen.countOfColumns + 1
        }
    }

    private func refreshScreen() {
        scroll()

        buffer = ""

        buffer.append("\u{1b}[?25l")
        buffer.append("\u{1b}[H")

        drawRows()

        buffer.append("\u{1b}[\(editorConfig.file.cursor.y - editorConfig.screen.rowOffset + 1);\((editorConfig.file.cursor.x - editorConfig.screen.columnOffset) + 1)H")

        buffer.append("\u{1b}[?25h")

        fileHandle.print(buffer)
    }

    private func drawRows() {
        for y in (0..<editorConfig.screen.countOfRows) {
            let fileRow = y + editorConfig.screen.rowOffset

            if (fileRow >= editorConfig.file.rows.count) {
                if editorConfig.file.rows.count == 0 && y == editorConfig.screen.countOfRows / 3 {
                    var message = String("SwiftKilo editor -- version \(versionString)".prefix(editorConfig.screen.countOfColumns))

                    var padding = (editorConfig.screen.countOfColumns - message.count) / 2
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
                buffer.append(String(editorConfig.file.rows[fileRow].dropFirst(editorConfig.screen.columnOffset).prefix(editorConfig.screen.countOfColumns)))
            }

            buffer.append("\u{1b}[K")
            if y < editorConfig.screen.countOfRows - 1 {
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
