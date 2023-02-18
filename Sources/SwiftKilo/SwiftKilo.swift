@main
public struct SwiftKilo {
    public private(set) var text = "Hello, World!"

    public static func main() {
        print(SwiftKilo().text)
    }
}
