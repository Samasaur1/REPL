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
signal(SIGINT) { _ in
    if task.isRunning {
        task.interrupt()
    } else {
        print()
        print(cmdPrompt, terminator: "")
        fflush(stdout)
    }
}
//func getch() -> Int {
//    var key: Int = 0
//    let c: cc_t = 0
//    let cct = (c, c, c, c, c, c, c, c, c, c, c, c, c, c, c, c, c, c, c, c) // Set of 20 Special Characters
//    var oldt: termios = termios(c_iflag: 0, c_oflag: 0, c_cflag: 0, c_lflag: 0, c_cc: cct, c_ispeed: 0, c_ospeed: 0)
//
//    tcgetattr(STDIN_FILENO, &oldt) // 1473
//    var newt = oldt
//    newt.c_lflag = 705//1217  // Reset ICANON and Echo off
//    tcsetattr( STDIN_FILENO, TCSANOW, &newt)
//    key = Int(getchar())  // works like "getch()"
//    tcsetattr( STDIN_FILENO, TCSANOW, &oldt)
//    return key
//}

//var buffer = UInt8(Double(getch()))
//Darwin.write(0, &buffer, 1)
//fwrite(&buffer, 1, 1, stdin)
//print(readLine())

//STDIN_FILENO
//Darwin.open(<#T##path: UnsafePointer<CChar>##UnsafePointer<CChar>#>, <#T##oflag: Int32##Int32#>, <#T##mode: mode_t##mode_t#>)
//fopen(<#T##__filename: UnsafePointer<Int8>!##UnsafePointer<Int8>!#>, <#T##__mode: UnsafePointer<Int8>!##UnsafePointer<Int8>!#>)
while true {
    print(cmdPrompt, terminator: "")
//    let codes = (getch(), getch(), getch())
//    print(getch(), terminator: "")
    guard let input = readLine() else {
        print()
        print("Exiting REPL")
        exit(0)
    }
    print(exec("\(command) \(input)"), terminator: "")
}
