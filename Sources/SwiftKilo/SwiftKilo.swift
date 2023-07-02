import Foundation
import AsyncAlgorithms
import System

let kVersionString = "0.1"
let kTabStop = 8
let kQuitTimes = 3

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
    struct Position {
        static let origin = Position(x: 0, y: 0)
        var x: Int
        var y: Int
    }

    struct Cursor {
        var position: Position

        enum Direction {
            case up
            case down
            case left
            case right
        }

        mutating func move(_ direction: Direction, distance: Int) {
            switch direction {
            case .up:
                position.y = position.y - distance
            case .down:
                position.y = position.y + distance
            case .left:
                position.x = position.x - distance
            case .right:
                position.x = position.x + distance
            }
        }
    }

    struct File {
        struct Row {
            var raw: String {
                didSet {
                    cook()
                }
            }
            var cooked: String {
                _cooked
            }

            private var _cooked = ""
            private mutating func cook() {
                let chopped = raw.enumerated().flatMap { i, egc in
                    guard egc == "\t" else { return [egc] }

                    return Array(repeating: Character(" "), count: kTabStop - (i % kTabStop))
                }
                _cooked = String(chopped)
            }

            init(raw: String) {
                self.raw = raw

                cook()
            }

            mutating func insert(_ chr: Character, at index: Int) {
                guard index < raw.count + 1 else { return }

                let stringIndex = raw.index(raw.startIndex, offsetBy: index)

                raw.insert(chr, at: stringIndex)
            }

            mutating func remove(at index: Int) {
                guard index < raw.count else { return }

                let stringIndex = raw.index(raw.startIndex, offsetBy: index)

                raw.remove(at: stringIndex)
            }
        }

        var path: String?
        var rows: [Row]
        var cursor: Cursor
        var isDirty: Bool

        var currentRow: Row? {
            guard cursor.position.y < rows.count else { return nil }

            return rows[cursor.position.y]
        }

        mutating func insertNewLine() {
            let content: String
            if cursor.position.y > rows.count {
                content = ""
            } else {
                content = String(rows[cursor.position.y].raw.prefix(cursor.position.x))
                rows[cursor.position.y].raw.removeFirst(min(cursor.position.x, rows[cursor.position.y].raw.count))
            }

            rows.insert(.init(raw: content), at: cursor.position.y)
            cursor.move(.down, distance: 1)
            cursor.move(.left, distance: cursor.position.x)

            isDirty = true
        }

        mutating func insert(_ char: Character) {
            if (cursor.position.y == rows.count) {
                rows.append(Row(raw: ""))
            }

            guard cursor.position.y < rows.count else { return }

            rows[cursor.position.y].insert(char, at: cursor.position.x)
            cursor.move(.right, distance: 1)

            isDirty = true
        }

        mutating func deleteCharacter() {
            if cursor.position.x > 0 {
                rows[cursor.position.y].remove(at: cursor.position.x - 1)
                cursor.move(.left, distance: 1)
            } else if cursor.position.y > 0 {
                let distance = rows[cursor.position.y - 1].raw.count

                rows[cursor.position.y - 1] = .init(raw: rows[cursor.position.y - 1].raw + rows[cursor.position.y].raw)
                rows.remove(at: cursor.position.y)

                cursor.move(.up, distance: 1)
                cursor.move(.right, distance: distance)
            } else {
                return
            }
            isDirty = true
        }

        mutating func save() throws {
            guard let path else { return }

            let url = URL(fileURLWithPath: path)

            try rows.map(\.raw).joined(separator: "\r\n").write(to: url, atomically: true, encoding: .utf8)

            isDirty = false
        }

        func find(for str: String) -> Position? {
            for (y, row) in rows.enumerated() {
                guard let range = row.raw.range(of: str) else { continue }

                let x = row.raw.distance(from: row.raw.startIndex, to: range.lowerBound)

                return Position(x: x, y: y)
            }

            return nil
        }
    }

    struct Screen {
        let countOfRows: Int
        let countOfColumns: Int

        var rowOffset: Int
        var columnOffset: Int
        var cursor: Cursor
    }

    struct StatusMessage {
        let content: String
        let didSetAt: Date

        init(content: String) {
            self.content = content
            self.didSetAt = Date()
        }
    }

    enum Mode {
        case normal
        case insert
    }

    struct EditorConfig {
        var screen: Screen
        var origTermios: termios
        var file: File
        var statusMessage: StatusMessage?
        var mode: Mode
        var quitTimes = kQuitTimes
    }

    public static func main() async throws {
        let args = CommandLine.arguments
        try await SwiftKilo(filePath: args.count > 1 ? args[1] : nil)?.main()
    }

    private let fileHandle: FileHandle
    private var editorConfig: EditorConfig!
    private var buffer = ""
    private var keyProcessor = KeyProcessor()

    init?(filePath: String?, fileHandle: FileHandle = .standardInput) {
        self.fileHandle = fileHandle

        guard let (height, width) = getWindowSize() else { return nil }

        editorConfig = EditorConfig(
            screen: Screen(countOfRows: height - 2, countOfColumns: width, rowOffset: 0, columnOffset: 0, cursor: Cursor(position: .origin)),
            origTermios: termios(),
            file: File(path: filePath, rows: [], cursor: Cursor(position: .origin), isDirty: false),
            mode: .normal
        )
    }

    deinit {
        disableRawMode()
    }

    private func main() async throws {
        enableRawMode()

        try openEditor()

        editorConfig.statusMessage = StatusMessage(content: "HELP: Ctrl-S = save | Ctrl-Q = quit")

        for try await scalar in merge(fileHandle.bytes.unicodeScalars.map({ (element: AsyncUnicodeScalarSequence<FileHandle.AsyncBytes>.Element) -> AsyncUnicodeScalarSequence<FileHandle.AsyncBytes>.Element? in element }), Interval(value: nil)) {
            refreshScreen()

            if let scalar,
               let action = keyProcessor.process(scalar, mode: editorConfig.mode) {
                switch action {
                // cursor
                case .moveCursorUp:
                    guard editorConfig.file.cursor.position.y > 0 else { break }

                    editorConfig.file.cursor.move(.up, distance: 1)
                case .moveCursorLeft:
                    guard editorConfig.file.cursor.position.x > 0 else { break }

                    editorConfig.file.cursor.move(.left, distance: 1)
                case .moveCursorRight:
                    guard editorConfig.file.cursor.position.x < editorConfig.file.currentRow?.raw.count ?? 0 else { break }

                    editorConfig.file.cursor.move(.right, distance: 1)
                case .moveCursorDown:
                    guard editorConfig.file.cursor.position.y < editorConfig.file.rows.count else { break }

                    editorConfig.file.cursor.move(.down, distance: 1)
                case .moveCursorToBeginningOfLine:
                    editorConfig.file.cursor.position.x = 0
                case .moveCursorToEndOfLine:
                    editorConfig.file.cursor.position.x = editorConfig.file.currentRow?.raw.count ?? 0
                // page
                case .movePageUp:
                    editorConfig.file.cursor.move(.up, distance: min(editorConfig.screen.countOfRows, editorConfig.file.cursor.position.y))
                case .movePageDown:
                    editorConfig.file.cursor.move(.down, distance: min(editorConfig.screen.countOfRows, editorConfig.file.rows.count - editorConfig.file.cursor.position.y))
                // text
                case .delete:
                    editorConfig.file.deleteCharacter()
                case .newLine:
                    editorConfig.file.insertNewLine()
                case .insert(let scalar):
                    editorConfig.file.insert(Character.init(scalar))
                // editor
                case .quit:
                    if editorConfig.file.isDirty && editorConfig.quitTimes > 0 {
                        editorConfig.statusMessage = .init(content: "WARNING!!! File has unsaved changes. Press Ctrl-Q \(editorConfig.quitTimes) more times to quit.")
                        editorConfig.quitTimes -= 1

                        break
                    }
                    fileHandle.print("\u{1b}[2J")
                    fileHandle.print("\u{1b}[H")

                    return
                case .changeModeToInput:
                    editorConfig.mode = .insert
                case .changeModeToNormal:
                    editorConfig.mode = .normal
                case .save:
                    do {
                        if (editorConfig.file.path ?? "").isEmpty {
                            var fileName: String? = nil
                            editorConfig.statusMessage = .init(content: "Save as: ")
                            refreshScreen()

                            for try await scalar in merge(fileHandle.bytes.unicodeScalars.map({ (element: AsyncUnicodeScalarSequence<FileHandle.AsyncBytes>.Element) -> AsyncUnicodeScalarSequence<FileHandle.AsyncBytes>.Element? in element }), Interval(value: nil)) {
                                guard let scalar else { continue }

                                if scalar == "\u{1b}" {
                                    fileName = nil
                                    break
                                }

                                let character = Character(scalar)

                                if character.isNewline,
                                   let fileName,
                                   fileName.count > 1 {
                                    break
                                }

                                if scalar == .init("h").modified(with: .control),
                                   let count = fileName?.count,
                                    count > 0 {
                                    fileName?.removeLast()
                                } else {
                                    if !(character.isASCII && character.isLetter) {
                                        continue
                                    }

                                    if fileName == nil {
                                        fileName = ""
                                    }
                                    fileName?.append(character)
                                }

                                editorConfig.statusMessage = .init(content: "Save as: \(fileName!)")
                                refreshScreen()
                            }

                            editorConfig.file.path = fileName
                        }

                        if (editorConfig.file.path ?? "").isEmpty {
                            editorConfig.statusMessage = .init(content: "Save aborted")
                        } else {
                            try editorConfig.file.save()
                            editorConfig.statusMessage = .init(content: "Saved")
                        }
                    } catch {
                        editorConfig.statusMessage = .init(content: "Can't save! I/O error: \(error.localizedDescription)")
                    }
                }

                switch action {
                case .quit:
                    break
                default:
                    editorConfig.quitTimes = kQuitTimes
                }

                if editorConfig.file.cursor.position.y >= editorConfig.file.rows.count {
                    editorConfig.file.cursor.position.x = 0
                } else {
                    editorConfig.file.cursor.position.x = min(editorConfig.file.cursor.position.x, editorConfig.file.currentRow?.raw.count ?? 0)
                }
            }
        }
    }

    // MARK: file i/o

    private func openEditor() throws {
        let rows: [File.Row]
        if let filePath = editorConfig.file.path,
           let data = FileManager.default.contents(atPath: filePath),
           let contents = String(data: data, encoding: .utf8) {
            rows = contents.split(whereSeparator: \.isNewline).map { line in
                return File.Row(raw: String(line))
            }
        } else {
            rows = []
        }

        editorConfig.file.rows = rows
    }

    // MARK: rendering

    private func scroll() {
        editorConfig.screen.cursor.position.x = editorConfig.file.currentRow?.raw.prefix(editorConfig.file.cursor.position.x).enumerated().reduce(0) { partialResult, e in
            let (i, char) = e
            let d: Int

            if char == "\t" {
                d = kTabStop - i % kTabStop
            } else {
                d = 1
            }

            return partialResult + d
        } ?? editorConfig.file.cursor.position.x

        if editorConfig.file.cursor.position.y < editorConfig.screen.rowOffset {
            editorConfig.screen.rowOffset = editorConfig.file.cursor.position.y
        }

        if editorConfig.file.cursor.position.y >= editorConfig.screen.rowOffset + editorConfig.screen.countOfRows {
            editorConfig.screen.rowOffset = editorConfig.file.cursor.position.y - editorConfig.screen.countOfRows + 1
        }

        if editorConfig.file.cursor.position.x < editorConfig.screen.columnOffset {
            editorConfig.screen.columnOffset = editorConfig.screen.cursor.position.x
        }

        if editorConfig.file.cursor.position.x >= editorConfig.screen.columnOffset + editorConfig.screen.countOfColumns {
            editorConfig.screen.columnOffset = editorConfig.screen.cursor.position.x - editorConfig.screen.countOfColumns + 1
        }
    }

    private func refreshScreen() {
        scroll()

        buffer = ""

        buffer.append("\u{1b}[?25l")
        buffer.append("\u{1b}[H")

        drawRows()
        buffer.append("\r\n")
        drawStatusBar()
        buffer.append("\r\n")
        drawMessageBar()

        buffer.append("\u{1b}[\(editorConfig.file.cursor.position.y - editorConfig.screen.rowOffset + 1);\((editorConfig.screen.cursor.position.x - editorConfig.screen.columnOffset) + 1)H")

        buffer.append("\u{1b}[?25h")

        fileHandle.print(buffer)
    }

    private func drawRows() {
        for y in (0..<editorConfig.screen.countOfRows) {
            let fileRow = y + editorConfig.screen.rowOffset

            if (fileRow >= editorConfig.file.rows.count) {
                if editorConfig.file.rows.count == 0 && y == editorConfig.screen.countOfRows / 3 {
                    var message = String("SwiftKilo editor -- version \(kVersionString)".prefix(editorConfig.screen.countOfColumns))

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
                buffer.append(String(editorConfig.file.rows[fileRow].cooked.dropFirst(editorConfig.screen.columnOffset).prefix(editorConfig.screen.countOfColumns)))
            }

            buffer.append("\u{1b}[K")

            if y < editorConfig.screen.countOfRows - 1 {
                buffer.append("\r\n")
            }
        }
    }

    private func drawStatusBar() {
        buffer.append("\u{1b}[7m")

        let lstatus = "\(editorConfig.file.path?.prefix(20) ?? "[No Name]") - \(editorConfig.file.rows.count) lines \(editorConfig.file.isDirty ? "(modified)" : "")"
        let rstatus = "\(editorConfig.file.cursor.position.y + 1)/\(editorConfig.file.rows.count)"

        if lstatus.count + rstatus.count <= editorConfig.screen.countOfColumns {
            buffer.append(([lstatus] + Array(repeating: " ", count: editorConfig.screen.countOfColumns - lstatus.count - rstatus.count) + [rstatus]).joined())
        } else {
            buffer.append(lstatus.padding(toLength: editorConfig.screen.countOfColumns, withPad: " ", startingAt: 0))
        }
        buffer.append("\u{1b}[m")
    }

    private func drawMessageBar() {
        buffer.append("\u{1b}[K")

        guard let statusMessage = editorConfig.statusMessage,
              statusMessage.didSetAt.distance(to: Date()) < 5 else { return }

        buffer.append(String(statusMessage.content.prefix(editorConfig.screen.countOfColumns)))
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
    case newLine
    case insert(UnicodeScalar)

    // MARK: editor
    case quit
    case changeModeToInput
    case changeModeToNormal
    case save
}
