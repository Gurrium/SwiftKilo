import Foundation

@main
public class SwiftKilo {
    public static func main() {
        SwiftKilo().main()
    }

    private var origTermios: termios

    init() {
        origTermios = termios()
    }

    deinit {
        disableRawMode()
    }

    private func main() {
        enableRawMode()

        var char: UInt8 = 0
        while read(FileHandle.standardInput.fileDescriptor, &char, 1) == 1 { // FIXME: ASCII外の文字を渡すと破滅しそう
            let scalar = Unicode.Scalar(char)
            guard scalar != "q" else { break }

            if CharacterSet.controlCharacters.contains(scalar) {
                print(scalar.value)
            } else {
                print("\(scalar.value) ('\(scalar)')")
            }
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
