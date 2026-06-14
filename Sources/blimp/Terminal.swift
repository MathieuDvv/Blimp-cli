import Foundation

// Terminal handles raw mode, key reading, and window size across all platforms.
// macOS + Linux: POSIX termios / poll / ioctl
// Windows:       WinSDK console APIs + VT processing

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif os(Windows)
import WinSDK
#endif

struct Terminal {

    // MARK: - Raw mode

    #if os(Windows)
    nonisolated(unsafe) static var savedInMode:  DWORD = 0
    nonisolated(unsafe) static var savedOutMode: DWORD = 0
    nonisolated(unsafe) static let hIn  = GetStdHandle(STD_INPUT_HANDLE)
    nonisolated(unsafe) static let hOut = GetStdHandle(STD_OUTPUT_HANDLE)
    #else
    nonisolated(unsafe) static var originalTermios = termios()
    #endif

    static func enableRawMode() {
        #if os(Windows)
        GetConsoleMode(hIn,  &savedInMode)
        GetConsoleMode(hOut, &savedOutMode)
        // Disable echo + line buffering on input
        let newIn = savedInMode & ~(DWORD(ENABLE_ECHO_INPUT) | DWORD(ENABLE_LINE_INPUT) | DWORD(ENABLE_PROCESSED_INPUT))
        SetConsoleMode(hIn, newIn)
        // Enable VT sequences + disable newline auto-return on output
        let ENABLE_VT:    DWORD = 0x0004
        let DISABLE_CRLF: DWORD = 0x0008
        SetConsoleMode(hOut, savedOutMode | ENABLE_VT | DISABLE_CRLF)
        // Hide cursor, enable SGR mouse (Windows Terminal supports this)
        print("\u{1B}[?25l\u{1B}[?1000h\u{1B}[?1006h", terminator: "")
        fflush(stdout)
        #else
        tcgetattr(STDIN_FILENO, &originalTermios)
        var raw = originalTermios
        raw.c_lflag &= ~(tcflag_t(ECHO) | tcflag_t(ICANON))
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
        print("\u{1B}[?25l\u{1B}[?1000h\u{1B}[?1015h\u{1B}[?1006h", terminator: "")
        fflush(stdout)
        #endif
    }

    static func disableRawMode() {
        #if os(Windows)
        SetConsoleMode(hIn,  savedInMode)
        SetConsoleMode(hOut, savedOutMode)
        print("\u{1B}[?25h\u{1B}[?1006l\u{1B}[?1000l\u{1B}[m\u{1B}[2J\u{1B}[H", terminator: "")
        fflush(stdout)
        #else
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &originalTermios)
        print("\u{1B}[?25h\u{1B}[?1006l\u{1B}[?1015l\u{1B}[?1000l\u{1B}[m\u{1B}[2J\u{1B}[H", terminator: "")
        fflush(stdout)
        #endif
    }

    // MARK: - Key reading

    static func readKey() -> [UInt8]? {
        #if os(Windows)
        return readKeyWindows()
        #else
        return readKeyPOSIX()
        #endif
    }

    #if os(Windows)
    private static func readKeyWindows() -> [UInt8]? {
        let wait = WaitForSingleObject(hIn, 50)
        guard wait == WAIT_OBJECT_0 else { return nil }
        var ir    = INPUT_RECORD()
        var count: DWORD = 0
        ReadConsoleInputW(hIn, &ir, 1, &count)
        guard ir.EventType == WORD(KEY_EVENT),
              ir.Event.KeyEvent.bKeyDown != 0 else { return nil }
        let vk = Int(ir.Event.KeyEvent.wVirtualKeyCode)
        let ch = ir.Event.KeyEvent.uChar.AsciiChar
        // Translate Windows VK codes to the same byte sequences as POSIX
        switch vk {
        case 0x26:  return [27, 91, 65]  // VK_UP    → ESC[A
        case 0x28:  return [27, 91, 66]  // VK_DOWN  → ESC[B
        case 0x27:  return [27, 91, 67]  // VK_RIGHT → ESC[C
        case 0x25:  return [27, 91, 68]  // VK_LEFT  → ESC[D
        case 0x0D:  return [13]           // VK_RETURN
        case 0x08:  return [127]          // VK_BACK
        case 0x1B:  return [27]           // VK_ESCAPE
        default:
            let ctrl = ir.Event.KeyEvent.dwControlKeyState
            if vk == 67 && (ctrl & DWORD(LEFT_CTRL_PRESSED) != 0 || ctrl & DWORD(RIGHT_CTRL_PRESSED) != 0) {
                return [3] // Ctrl+C
            }
            let byte = UInt8(bitPattern: ch)
            return byte >= 32 ? [byte] : nil
        }
    }
    #else
    private static func readKeyPOSIX() -> [UInt8]? {
        var pfd = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
        guard poll(&pfd, 1, 50) > 0 else { return nil }
        var buf = [UInt8](repeating: 0, count: 1)
        guard read(STDIN_FILENO, &buf, 1) == 1 else { return nil }
        if buf[0] == 27 {
            if poll(&pfd, 1, 0) <= 0 { return buf }
            var seq = [UInt8](repeating: 0, count: 2)
            if read(STDIN_FILENO, &seq, 2) != 2 { return buf }
            buf.append(contentsOf: seq)
            if seq[0] == 91 && seq[1] == 60 { // SGR mouse
                while true {
                    var m = [UInt8](repeating: 0, count: 1)
                    if read(STDIN_FILENO, &m, 1) == 1 {
                        buf.append(m[0])
                        if m[0] == 77 || m[0] == 109 { break }
                    } else { break }
                }
            }
        }
        return buf
    }
    #endif

    // MARK: - Window size

    static func getWindowSize() -> (rows: Int, cols: Int) {
        #if os(Windows)
        var csbi = CONSOLE_SCREEN_BUFFER_INFO()
        GetConsoleScreenBufferInfo(hOut, &csbi)
        let cols = Int(csbi.srWindow.Right  - csbi.srWindow.Left + 1)
        let rows = Int(csbi.srWindow.Bottom - csbi.srWindow.Top  + 1)
        return (rows: max(10, rows), cols: max(40, cols))
        #else
        var w = winsize()
        if ioctl(STDOUT_FILENO, TIOCGWINSZ, &w) == -1 { return (24, 80) }
        return (Int(w.ws_row), Int(w.ws_col))
        #endif
    }
}
