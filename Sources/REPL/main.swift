import Foundation

let command = CommandLine.arguments.dropFirst().joined(separator: " ")
//func posix_exec(_ args: [String]) {
//    var pid: pid_t = 0
//    let args = ["/usr/bin/env", "bash", "-i", "-c", #"echo "$PS1""#]
//    let c_args = args.map { $0.withCString(strdup)! }
//    posix_spawn(&pid, c_args[0], nil, nil, c_args + [nil], environ)
//    waitpid(pid, nil, 0)
//}

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

// MARK: - Extract PS1
//   (via `bash -i -c 'echo "$PS1"'`)
var action: posix_spawn_file_actions_t? = nil
posix_spawn_file_actions_init(&action);
defer { posix_spawn_file_actions_destroy(&action) }
let m: mode_t = S_IRWXU | S_IRWXG | S_IRWXO
posix_spawn_file_actions_addopen(&action, 1, "/tmp/ps1", (O_WRONLY | O_CREAT | O_TRUNC), m)
//posix_spawn_file_actions_adddup2(&action, 1, 2)

let args = ["/usr/bin/env", "bash", "-i", "-c", #"echo -n "$PS1""#]
let c_args = args.map { $0.withCString(strdup)! }
defer { for arg in c_args { free(arg) } }

var pid = pid_t()
let rv = posix_spawnp(&pid, c_args[0], &action, nil, c_args + [nil], environ)
guard rv == 0 else {
  // Should get errno
  exit(1)
}
print(pid)

var exitCode: Int32 = 0
waitpid(pid, &exitCode, 0)

//print("Process exited with code \(exitCode)")

let rawPS1 = try! String(contentsOfFile: "/tmp/ps1")

// MARK: Convert to coloring, replacements, etc.
//let s = String(contentsOfFile: .init(fileURLWithPath: "/tmp/ps1"))
let convertedPS1 = rawPS1.replacingOccurrences(of: #"\033"#, with: "\u{001B}").replacingOccurrences(of: #"\e"#, with: "\u{001B}") //escape chars
                        .replacingOccurrences(of: #"\["#, with: "").replacingOccurrences(of: #"\]"#, with: "") //used to tell bash the're format chars and not printed
                        .replacingOccurrences(of: #"\w"#, with: ProcessInfo.processInfo.environment["PWD"]!.replacingOccurrences(of: "/Users/\(ProcessInfo.processInfo.userName)", with: "~")) //current working directory
                        .replacingOccurrences(of: #"\W"#, with: ProcessInfo.processInfo.environment["PWD"]!.split(separator: "/").last!) //CWD basename
                        //.replacingOccurrences(of: #"\d"#, with: "df.dateFormat = "E MMM d"") //should be done every time we print prompt
                        .replacingOccurrences(of: #"\h"#, with: ProcessInfo.processInfo.hostName)
                        .replacingOccurrences(of: #"\H"#, with: ProcessInfo.processInfo.hostName)
                        .replacingOccurrences(of: #"\j"#, with: "0") //jobs — since we won't allow backgrounding, always 0
                        .replacingOccurrences(of: #"\l"#, with: "[repl]") //"The basename of the shell's terminal device name." We don't have one
                        .replacingOccurrences(of: #"\s"#, with: CommandLine.arguments[0].split(separator: "/").last!) //"The name of the shell, the basename of $0 (the portion following the final slash)."
                        //.replOcc("t", "T", "@") //time, must be done every time we print prompt
                        //\t   The time, in 24-hour HH:MM:SS format. 
                        //\T   The time, in 12-hour HH:MM:SS format. 
                        //\@   The time, in 12-hour am/pm format.
                        .replacingOccurrences(of: #"\u"#, with: ProcessInfo.processInfo.userName)
                        .replacingOccurrences(of: #"\v"#, with: "1.0") //version major.minor, no patch
                        .replacingOccurrences(of: #"\v"#, with: "1.0.0") //version major.minor.patch
                        //.replacingOccurrences(of: #"\!"#, with: "1.0") //history number
                        //.replacingOccurrences(of: #"\#"#, with: "1.0") //command number (i.e. length of commands list)
                        //.replacingOccurrences(of: #"\$"#, with: "1.0") //'#' iff root else '$'
print(convertedPS1)
let cmdPrompt = convertedPS1 + "\u{001B}[1;32m\(command)\u{001B}[00m "

// MARK: - Begin REPL
print("Initializing REPL with command: \(command)")
print("Use ^D to exit")
print()

var key: Int = 0
let c: cc_t = 0
let cct = (c, c, c, c, c, c, c, c, c, c, c, c, c, c, c, c, c, c, c, c) // Set of 20 Special Characters
var originalTerm: termios = termios(c_iflag: 0, c_oflag: 0, c_cflag: 0, c_lflag: 0, c_cc: cct, c_ispeed: 0, c_ospeed: 0)
tcgetattr(STDIN_FILENO, &originalTerm) //this gets the current settings
var term = originalTerm
term.c_lflag &= ~(UInt(Darwin.ECHO) | UInt(Darwin.ICANON)) //turn off ECHO and ICANON
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
        print("^C")
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
                if charIdx == chars.count {
                    chars.append(c)
                } else {
                    chars[charIdx] = c
                }
                charIdx += 1
                print(Character(UnicodeScalar(UInt32(c2))!), terminator: "")
                if charIdx == chars.count {
                    chars.append(c2)
                } else {
                    chars[charIdx] = c2
                }
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
            if chars.isEmpty || charIdx == 0 {
                tputBel()
            } else {
                print("\u{001B}[1D", terminator: "")
                print(String(chars[charIdx..<chars.endIndex].map { Character(UnicodeScalar(UInt32($0))!) }), terminator: "")
                print(" ", terminator: "")//clear line from cursor to end of line
                    //I'm aware there is an ANSI control code to do this to end of the line,
                    //  but I'm just deleting one character, so I only need to overwrite one char.
                for _ in 0..<(chars[charIdx..<chars.endIndex].count + 1) {//'go back' for every character that was printed
                    print("\u{001B}[1D", terminator: "")
                }
                chars.remove(at: charIdx - 1)
                charIdx -= 1

                //This should have worked, but it didn't.
//                print("\u{001B}[1D", terminator: "")
//                print("\u{001B}[s", terminator: "")//store cursor position
//                print(String(chars[charIdx..<chars.endIndex].map { Character(UnicodeScalar(UInt32($0))!) }), terminator: "")
//                print(" ", terminator: "")//clear line from cursor to end of line
//                    //I'm aware there is an ANSI control code to do this to end of the line,
//                    //  but I'm just deleting one character, so I only need to overwrite one char.
//                print("\u{001B}[u", terminator: "")//load cursor position
//                chars.remove(at: charIdx - 1)
//                charIdx -= 1
            }
        } else {
            print(Character(UnicodeScalar(UInt32(c))!), terminator: "")
            if charIdx == chars.count {
                chars.append(c)
            } else {
                chars[charIdx] = c
            }
            charIdx += 1
        }
    }
}
