@main
public struct SwiftKilo {
    public static func main() {
        while let str = readLine(),
              str != "q" {
            print(str)
        }
    }
}
