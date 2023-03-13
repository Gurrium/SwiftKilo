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

        let keyPath = \String.count

        let shouldWaitFlag = Container(content: true)
        let iterator = Container(content: FileHandle.standardInput.bytes.characters.makeAsyncIterator())

        let readTask = Task.detached {
            return try await iterator.content
        }

        let timeoutTask = Task.detached {
            while await shouldWaitFlag.content {
                try await Task.sleep(nanoseconds: 1_000)
            }


        }

        for try await character in FileHandle.standardInput.bytes.characters {
            guard character != "q" else { break }

            print(character)
        }
    }

    private func enableRawMode() {
        tcgetattr(STDIN_FILENO, &origTermios)

        var new = origTermios
        new.c_lflag &= ~tcflag_t(ECHO | ICANON | ISIG)

        tcsetattr(STDIN_FILENO, TCSAFLUSH, &new)
    }

    private func disableRawMode() {
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &origTermios)
    }
}

actor Container<T> {
    var content: T

    init(content: T) {
        self.content = content
    }

    func set(_ content: T) {
        self.content = content
    }
}

extension Container where T: AsyncIteratorProtocol {
    func next() async throws -> T.Element? {
        try await content.next()
    }
}
