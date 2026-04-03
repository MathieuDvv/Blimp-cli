import Foundation
import Darwin

struct Terminal {
    nonisolated(unsafe) static var originalTermios = termios()

    static func enableRawMode() {
        tcgetattr(STDIN_FILENO, &originalTermios)
        var raw = originalTermios

        raw.c_lflag &= ~UInt(ECHO | ICANON)

        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)

        print("\u{1B}[?25l\u{1B}[?1000h\u{1B}[?1015h\u{1B}[?1006h", terminator: "")
        fflush(stdout)
    }

    static func disableRawMode() {
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &originalTermios)
        print("\u{1B}[?25h\u{1B}[?1006l\u{1B}[?1015l\u{1B}[?1000l\u{1B}[m\u{1B}[2J\u{1B}[H", terminator: "")
        fflush(stdout)
    }

    static func readKey() -> [UInt8]? {
        var pfd = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
        let ret = poll(&pfd, 1, 50)
        if ret <= 0 { return nil }

        var buf = [UInt8](repeating: 0, count: 1)
        let n = read(STDIN_FILENO, &buf, 1)
        if n != 1 { return nil }

        if buf[0] == 27 {
            if poll(&pfd, 1, 0) <= 0 { return buf }
            var seq = [UInt8](repeating: 0, count: 2)
            if read(STDIN_FILENO, &seq, 2) != 2 { return buf }
            buf.append(contentsOf: seq)

            if seq[0] == 91 && seq[1] == 60 {
                while true {
                    var m = [UInt8](repeating: 0, count: 1)
                    if read(STDIN_FILENO, &m, 1) == 1 {
                        buf.append(m[0])
                        if m[0] == 77 || m[0] == 109 {
                            break
                        }
                    } else {
                        break
                    }
                }
            }
        }
        return buf
    }

    static func getWindowSize() -> (rows: Int, cols: Int) {
        var w = winsize()
        if ioctl(STDOUT_FILENO, TIOCGWINSZ, &w) == -1 {
            return (24, 80)
        }
        return (Int(w.ws_row), Int(w.ws_col))
    }
}
