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

        mutating func move(to position: Position) {
            self.position = position
        }
    }

    struct File {
        struct Row {
            var raw: String

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

            mutating func removeFirst(_ k: Int = 1) {
                raw.removeFirst(k)
            }

            mutating func prefix(_ maxLength: Int = 1) -> Substring {
                raw.prefix(maxLength)
            }
        }

        private(set) var rows: [Row]
        private(set) var cursor = Cursor(position: .origin)
        private(set) var isDirty = false


        var currentRow: Row? {
            guard cursor.position.y < rows.count else { return nil }

            return rows[cursor.position.y]
        }

        init(path: String?) {
            if let path,
               let data = FileManager.default.contents(atPath: path),
               let contents = String(data: data, encoding: .utf8) {
                rows = contents.split(whereSeparator: \.isNewline).map { line in
                    return File.Row(raw: String(line))
                }
            } else {
                rows = []
            }
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

        mutating func save(to path: String) throws {
            let url = URL(fileURLWithPath: path)

            try rows.map(\.raw).joined(separator: "\r\n").write(to: url, atomically: true, encoding: .utf8)

            isDirty = false
        }

        func find(_ str: String, forward: Bool, from startPosition: Position) -> Position? {
            var rowsBefore = Array(rows[0..<startPosition.y])
            var rowsAfter = Array(rows[startPosition.y..<rows.endIndex])

            if !rowsAfter.isEmpty {
                rowsBefore.append(Row(raw: String(rowsAfter[0].prefix(startPosition.x))))
                rowsAfter[0].removeFirst(startPosition.x)
            }

            if forward {
                for (y, row) in rowsAfter.enumerated() {
                    guard let range = row.raw.range(of: str) else { continue }

                    let x = row.raw.distance(from: row.raw.startIndex, to: range.lowerBound)

                    return Position(x: y == 0 ? x + startPosition.x : x, y: y + startPosition.y)
                }

                for (y, row) in rowsBefore.enumerated() {
                    guard let range = row.raw.range(of: str) else { continue }

                    let x = row.raw.distance(from: row.raw.startIndex, to: range.lowerBound)

                    return Position(x: x, y: y)
                }

                return nil
            } else {
                if let currentRow,
                   let range = currentRow.raw.range(of: str)
                {
                    let x = currentRow.raw.distance(from: currentRow.raw.startIndex, to: range.lowerBound)

                    if x < startPosition.x {
                        return Position(x: x, y: startPosition.y)
                    }
                }

                let str = String(str.reversed())
                for (reversedY, row) in rowsBefore.reversed().enumerated() {
                    let raw = String(row.raw.reversed())

                    guard let range = raw.range(of: str) else { continue }

                    let x = raw.distance(from: range.upperBound, to: raw.endIndex)

                    return Position(x: x, y: rowsBefore.count - 1 - reversedY)
                }

                for (reversedY, row) in rowsAfter.reversed().enumerated() {
                    let raw = String(row.raw.reversed())

                    guard let range = raw.range(of: str) else { continue }

                    let x = raw.distance(from: range.upperBound, to: raw.endIndex)

                    return Position(x: x, y: startPosition.y + rowsAfter.count - reversedY - 1)
                }

                return nil
            }
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

    struct Editor {
        struct SearchResult {
            var target: String
            var position: Position?
        }

        var screen: Screen
        var origTermios: termios
        var file: File {
            didSet {
                buildRows()
            }
        }
        var statusMessage: StatusMessage?
        var mode = Mode.normal
        var quitTimes = kQuitTimes
        var lastSearchResult: SearchResult?

        var rows: [String] = []
        private mutating func buildRows() {
            rows = file.rows.map { row in
                let chopped = row.raw.enumerated().flatMap { i, egc in
                    if egc == "\t" {
                        return Array(repeating: Character(" "), count: kTabStop - (i % kTabStop))
                    } else if "0123456789".contains(where: { $0 == egc }) {
                        return Array("\u{1b}[31m") + [egc] + Array("\u{1b}[39m")
                    } else {
                        return  [egc]
                    }
                }

                return String(chopped)
            }
        }

        private var path: String

        init(
            screen: Screen,
            origTermios: termios,
            path: String?
        ) {
            self.screen = screen
            self.origTermios = origTermios
            self.path = path ?? "tmp"
            self.file = File(path: self.path)

            buildRows()
        }

        private mutating func find(_ str: String, forward: Bool, from startPosition: Position) -> Position? {
            let matchedPosition = file.find(str, forward: forward, from: startPosition)

            lastSearchResult = SearchResult(target: str, position: matchedPosition)

            return matchedPosition
        }

        mutating func find(_ str: String) -> Position? {
            find(str, forward: true, from: file.cursor.position)
        }

        mutating func findNext() -> Position? {
            guard let lastSearchResult else { return nil }

            var position = file.cursor.position
            position.x += 1

            return find(lastSearchResult.target, forward: true, from: position)
        }

        mutating func findPrevious() -> Position? {
            guard let lastSearchResult else { return nil }

            return find(lastSearchResult.target, forward: false, from: file.cursor.position)
        }
    }

    public static func main() async throws {
        let args = CommandLine.arguments
        try await SwiftKilo(filePath: args.count > 1 ? args[1] : nil)?.main()
    }

    private let fileHandle: FileHandle
    private var editor: Editor!
    private var buffer = ""
    private var keyProcessor = KeyProcessor()

    init?(filePath: String?, fileHandle: FileHandle = .standardInput) {
        self.fileHandle = fileHandle

        guard let (height, width) = getWindowSize() else { return nil }

        editor = Editor(
            screen: Screen(countOfRows: height - 2, countOfColumns: width, rowOffset: 0, columnOffset: 0, cursor: Cursor(position: .origin)),
            origTermios: termios(),
            path: filePath
        )
    }

    deinit {
        disableRawMode()
    }

    private func main() async throws {
        enableRawMode()
//
//        try openEditor()

        editor.statusMessage = StatusMessage(content: "HELP: Ctrl-S = save | Ctrl-Q = quit | / = find")

        for try await scalar in merge(fileHandle.bytes.unicodeScalars.map({ (element: AsyncUnicodeScalarSequence<FileHandle.AsyncBytes>.Element) -> AsyncUnicodeScalarSequence<FileHandle.AsyncBytes>.Element? in element }), Interval(value: nil)) {
            refreshScreen()

            if let scalar,
               let action = keyProcessor.process(scalar, mode: editor.mode) {
                switch action {
                // cursor
                case .moveCursorUp:
                    guard editor.file.cursor.position.y > 0 else { break }

                    editor.file.cursor.move(.up, distance: 1)
                case .moveCursorLeft:
                    guard editor.file.cursor.position.x > 0 else { break }

                    editor.file.cursor.move(.left, distance: 1)
                case .moveCursorRight:
                    guard editor.file.cursor.position.x < editor.file.currentRow?.raw.count ?? 0 else { break }

                    editor.file.cursor.move(.right, distance: 1)
                case .moveCursorDown:
                    guard editor.file.cursor.position.y < editor.file.rows.count else { break }

                    editor.file.cursor.move(.down, distance: 1)
                case .moveCursorToBeginningOfLine:
                    editor.file.cursor.position.x = 0
                case .moveCursorToEndOfLine:
                    editor.file.cursor.position.x = editor.file.currentRow?.raw.count ?? 0
                // page
                case .movePageUp:
                    editor.file.cursor.move(.up, distance: min(editor.screen.countOfRows, editor.file.cursor.position.y))
                case .movePageDown:
                    editor.file.cursor.move(.down, distance: min(editor.screen.countOfRows, editor.file.rows.count - editor.file.cursor.position.y))
                // text
                case .delete:
                    editor.file.deleteCharacter()
                case .newLine:
                    editor.file.insertNewLine()
                case .insert(let scalar):
                    editor.file.insert(Character.init(scalar))
                // editor
                case .quit:
                    if editor.file.isDirty && editor.quitTimes > 0 {
                        editor.statusMessage = .init(content: "WARNING!!! File has unsaved changes. Press Ctrl-Q \(editor.quitTimes) more times to quit.")
                        editor.quitTimes -= 1

                        break
                    }
                    fileHandle.print("\u{1b}[2J")
                    fileHandle.print("\u{1b}[H")

                    return
                case .changeModeToInput:
                    editor.mode = .insert
                case .changeModeToNormal:
                    editor.mode = .normal
                case .save:
                    do {
                        if (editor.file.path ?? "").isEmpty {
                            editor.statusMessage = .init(content: "Save as:")
                            refreshScreen()

                            for try await input in AsyncPromptInputSequence(fileHandle: fileHandle) {
                                switch input {
                                case .content(let content), .submit(let content):
                                    editor.file.path = content
                                    editor.statusMessage = .init(content: "Save as: \(content)")
                                    refreshScreen()
                                case .terminate:
                                    editor.file.path = nil
                                }
                            }

                            editor.statusMessage = .init(content: "")
                            refreshScreen()
                        }

                        if editor.file.path == nil {
                            editor.statusMessage = .init(content: "Save aborted")
                        } else {
                            try editor.file.save()
                            editor.statusMessage = .init(content: "Saved")
                        }
                    } catch {
                        editor.statusMessage = .init(content: "Can't save! I/O error: \(error.localizedDescription)")
                    }
                case .find:
                    let previousCursorPosition = editor.file.cursor.position
                    var didFind = false

                    editor.statusMessage = .init(content: "Search:")
                    refreshScreen()

                    awaitInput: for try await input in AsyncPromptInputSequence(fileHandle: fileHandle) {
                        switch input {
                        case .content(let content), .submit(let content):
                            editor.statusMessage = .init(content: "Search: \(content)")
                            refreshScreen()
                            if let position = editor.find(content) {
                                editor.file.cursor.move(to: position)
                                didFind = true
                            } else {
                                didFind = false
                            }
                        case .terminate:
                            break awaitInput
                        }
                    }

                    editor.statusMessage = .init(content: "")
                    refreshScreen()

                    if !didFind {
                        editor.file.cursor.move(to: previousCursorPosition)
                    }
                case .findForward:
                    if let position = editor.findNext() {
                        editor.file.cursor.move(to: position)
                    }
                case .findBackward:
                    if let position = editor.findPrevious() {
                        editor.file.cursor.move(to: position)
                    }
                }

                switch action {
                case .quit:
                    break
                default:
                    editor.quitTimes = kQuitTimes
                }

                if editor.file.cursor.position.y >= editor.file.rows.count {
                    editor.file.cursor.position.x = 0
                } else {
                    editor.file.cursor.position.x = min(editor.file.cursor.position.x, editor.file.currentRow?.raw.count ?? 0)
                }
            }
        }
    }

    // TODO: 一般化する
    // MARK: prompt

    struct AsyncPromptInputSequence: AsyncSequence, AsyncIteratorProtocol {
        enum PromptInput {
            case content(String)
            case terminate
            case submit(String)
        }

        typealias Element = PromptInput

        private let fileHandle: FileHandle
        private var unicodeScalarsIterator: AsyncUnicodeScalarSequence<FileHandle.AsyncBytes>.AsyncIterator
        private var partialResult = ""
        private var isFinished = false

        init(fileHandle: FileHandle) {
            self.fileHandle = fileHandle
            unicodeScalarsIterator = fileHandle.bytes.unicodeScalars.makeAsyncIterator()
        }

        func makeAsyncIterator() -> AsyncPromptInputSequence {
            self
        }

        mutating func next() async throws -> PromptInput? {
            guard !isFinished else { return nil }

            guard let scalar = try await unicodeScalarsIterator.next(),
                  scalar != "\u{1b}"
            else {
                isFinished = true
                return .terminate
            }

            let character = Character(scalar)

            if character.isNewline,
               partialResult.count > 1 {
                isFinished = true
                return .submit(partialResult)
            }

            if scalar == .init("h").modified(with: .control),
               partialResult.count > 0 {
                partialResult.removeLast()
            } else {
                partialResult.append(character)
            }

            return .content(partialResult)
        }
    }

    // MARK: rendering

    private func scroll() {
        editor.screen.cursor.position.x = editor.file.currentRow?.raw.prefix(editor.file.cursor.position.x).enumerated().reduce(0) { partialResult, e in
            let (i, char) = e
            let d: Int

            if char == "\t" {
                d = kTabStop - i % kTabStop
            } else {
                d = 1
            }

            return partialResult + d
        } ?? editor.file.cursor.position.x

        if editor.file.cursor.position.y < editor.screen.rowOffset {
            editor.screen.rowOffset = editor.file.cursor.position.y
        }

        if editor.file.cursor.position.y >= editor.screen.rowOffset + editor.screen.countOfRows {
            editor.screen.rowOffset = editor.file.cursor.position.y - editor.screen.countOfRows + 1
        }

        if editor.file.cursor.position.x < editor.screen.columnOffset {
            editor.screen.columnOffset = editor.screen.cursor.position.x
        }

        if editor.file.cursor.position.x >= editor.screen.columnOffset + editor.screen.countOfColumns {
            editor.screen.columnOffset = editor.screen.cursor.position.x - editor.screen.countOfColumns + 1
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

        buffer.append("\u{1b}[\(editor.file.cursor.position.y - editor.screen.rowOffset + 1);\((editor.screen.cursor.position.x - editor.screen.columnOffset) + 1)H")

        buffer.append("\u{1b}[?25h")

        fileHandle.print(buffer)
    }

    private func drawRows() {
        for y in (0..<editor.screen.countOfRows) {
            let rowNum = y + editor.screen.rowOffset

            if (rowNum >= editor.rows.count) {
                if editor.rows.count == 0 && y == editor.screen.countOfRows / 3 {
                    var message = String("SwiftKilo editor -- version \(kVersionString)".prefix(editor.screen.countOfColumns))

                    var padding = (editor.screen.countOfColumns - message.count) / 2
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
                buffer.append(String(editor.rows[rowNum].dropFirst(editor.screen.columnOffset).prefix(editor.screen.countOfColumns)))
            }

            buffer.append("\u{1b}[K")

            if y < editor.screen.countOfRows - 1 {
                buffer.append("\r\n")
            }
        }
    }

    private func drawStatusBar() {
        buffer.append("\u{1b}[7m")

        let lstatus = "\(editor.file.path?.prefix(20) ?? "[No Name]") - \(editor.rows.count) lines \(editor.file.isDirty ? "(modified)" : "")"
        let rstatus = "\(editor.file.cursor.position.y + 1)/\(editor.rows.count)"

        if lstatus.count + rstatus.count <= editor.screen.countOfColumns {
            buffer.append(([lstatus] + Array(repeating: " ", count: editor.screen.countOfColumns - lstatus.count - rstatus.count) + [rstatus]).joined())
        } else {
            buffer.append(lstatus.padding(toLength: editor.screen.countOfColumns, withPad: " ", startingAt: 0))
        }
        buffer.append("\u{1b}[m")
    }

    private func drawMessageBar() {
        buffer.append("\u{1b}[K")

        guard let statusMessage = editor.statusMessage,
              statusMessage.didSetAt.distance(to: Date()) < 5 else { return }

        buffer.append(String(statusMessage.content.prefix(editor.screen.countOfColumns)))
    }

    private func getWindowSize() -> (height: Int, width: Int)? {
        var windowSize = winsize()

        guard ioctl(fileHandle.fileDescriptor, TIOCGWINSZ, &windowSize) != -1 else { return nil }

        return (height: Int(windowSize.ws_row), width: Int(windowSize.ws_col))
    }

    private func enableRawMode() {
        tcgetattr(STDIN_FILENO, &editor.origTermios)

        var new = editor.origTermios
        new.c_iflag &= ~tcflag_t(BRKINT | ICRNL | INPCK | ISTRIP | IXON)
        new.c_oflag &= ~tcflag_t(OPOST)
        new.c_cflag |= tcflag_t(CS8)
        new.c_lflag &= ~tcflag_t(ECHO | ICANON | IEXTEN | ISIG)

        tcsetattr(STDIN_FILENO, TCSAFLUSH, &new)
    }

    private func disableRawMode() {
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &editor.origTermios)
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
    case find
    case findForward
    case findBackward
}
