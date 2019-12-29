import Foundation

let command = CommandLine.arguments.dropFirst().joined(separator: " ")
let cmdPrompt = "\u{001B}[38;5;9m[\(NSUserName())]\u{001B}[1;34m(\(FileManager.default.currentDirectoryPath.replacingOccurrences(of: "/Users/\(NSUserName())", with: "~")))\u{001B}[m\u{001B}[1;32m$ \(command)\u{001B}[00m "

var task: Process = Process()
func exec(_ command: String) -> String {
    task = Process()
    task.launchPath = "/bin/bash"
    task.arguments = ["-c", command]
    
    let pipe = Pipe()
    task.standardOutput = pipe
    task.launch()
    
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output: String = NSString(data: data, encoding: String.Encoding.utf8.rawValue)! as String
    
    return output
}

print("Initializing REPL with command: \(command)")
print("Use ^D to exit")
print()

var key: Int = 0
let c: cc_t = 0
let cct = (c, c, c, c, c, c, c, c, c, c, c, c, c, c, c, c, c, c, c, c) // Set of 20 Special Characters
var originalTerm: termios = termios(c_iflag: 0, c_oflag: 0, c_cflag: 0, c_lflag: 0, c_cc: cct, c_ispeed: 0, c_ospeed: 0)
tcgetattr(STDIN_FILENO, &originalTerm) //this gets the current settings
var term = originalTerm
term.c_lflag &= (UInt.max ^ UInt(Darwin.ECHO) ^ UInt(Darwin.ICANON)) //turn off ECHO and ICANON
tcsetattr(STDIN_FILENO, TCSANOW, &term) //set these new settings

func resetTermAndExitWith(sig: Int32) {
    tcsetattr(STDIN_FILENO, TCSANOW, &originalTerm)
    exit(sig)
}
signal(SIGKILL, resetTermAndExitWith(sig:))
signal(SIGTERM, resetTermAndExitWith(sig:))
signal(SIGQUIT, resetTermAndExitWith(sig:))
signal(SIGSTOP, resetTermAndExitWith(sig:))

var chars: [Int32] = []
var charIdx = 0
var commands: [String] = [""]
var cmdIdx = 0

signal(SIGINT) { _ in
    if task.isRunning {
        task.interrupt()
    } else {
        print()
        chars = []
        charIdx = 0
        cmdIdx = 0
        print(cmdPrompt, terminator: "")
        fflush(stdout)
    }
}

func tputBel() {
    var v = UInt8(7)
    write(STDOUT_FILENO, &v, 1)
}

while true {
    print(cmdPrompt, terminator: "")
    while true {
        let c = getchar()
        if c == 27 { //[ (first part of arrow keys)
            let c2 = getchar()
            if c2 == 91 {
                let c3 = getchar()
                switch c3 {
                case 65:
//                    print("↑")
                    if commands.count > cmdIdx + 1 {
                        cmdIdx += 1
                        print("\u{001B}[2K", terminator: "")
                        print("\r\(cmdPrompt)\(commands[cmdIdx])", terminator: "")
                        chars = commands[cmdIdx].map { Int32($0.unicodeScalars.first!.value) }
                    } else {
                        tputBel()
                    }
                case 67:
//                    print("→")
                    if charIdx <= chars.count - 1 {
                        print("\u{001B}[1C", terminator: "")
                        charIdx += 1
                    } else {
                        tputBel()
                    }
                case 66:
//                    print("↓")
                    if cmdIdx >= 1 {
                        cmdIdx -= 1
                        print("\u{001B}[2K", terminator: "")
                        print("\r\(cmdPrompt)\(commands[cmdIdx])", terminator: "")
                        chars = commands[cmdIdx].map { Int32($0.unicodeScalars.first!.value) }
                    } else {
                        tputBel()
                    }
                case 68:
//                    print("←")
                    if charIdx > 0 {
                        print("\u{001B}[1D", terminator: "")
                        charIdx -= 1
                    } else {
                        tputBel()
                    }
                default:
                    print("", terminator: "")
                }
            } else {
                print(Character(UnicodeScalar(UInt32(c))!), terminator: "")
                chars.append(c)
                charIdx += 1
                print(Character(UnicodeScalar(UInt32(c2))!), terminator: "")
                chars.append(c2)
                charIdx += 1
            }
        } else if c == 10 { //\n
            print()
            if !chars.isEmpty {
                let input = String(chars.map { Character(UnicodeScalar(UInt32($0))!) })
                print(exec("\(command) \(input)"), terminator: "")
                commands.append(input)
            }
            chars = []
            charIdx = 0
            break
        } else if c == 4 { //^D
            if chars.isEmpty {
                print("^D")
                print("Exiting REPL")
                resetTermAndExitWith(sig: 0)
            } else {
                tputBel()
            }
        } else if c == 127 { //backspace/^H
            if chars.isEmpty {
                tputBel()
            } else {
                print("\u{001B}[1D \u{001B}[1D", terminator: "")
                chars.removeLast()
                charIdx -= 1
            }
        } else {
            print(Character(UnicodeScalar(UInt32(c))!), terminator: "")
            chars.append(c)
            charIdx += 1
        }
    }
}
