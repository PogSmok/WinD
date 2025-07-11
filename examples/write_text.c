#include <windows.h>
#include <stdio.h>

// Typedef for write_text: int write_text(WCHAR* buffer, DWORD len, CHAR cursor_persist);
typedef int (__cdecl *write_text_t)(WCHAR*, DWORD, CHAR);

int main() {
    // Load WinD DLL
    HMODULE hDll = LoadLibraryW(L"wind.dll");
    if (!hDll) {
        wprintf(L"Failed to load DLL\n");
        return 1;
    }

    write_text_t write_text = (write_text_t)GetProcAddress(hDll, "write_text");
    if (!write_text) {
        wprintf(L"Failed to find write_text\n");
        FreeLibrary(hDll);
        return 1;
    }

    // UTF-16 string with various ANSI escape codes:
    // Red text, green background, bold, underline, and reset
    WCHAR text[] =
        L"\x1b[31mRed text\x1b[0m and \x1b[32mgreen text\x1b[0m with normal text.\n"
        L"\x1b[1mBold text\x1b[22m, \x1b[3mitalic text\x1b[23m, and \x1b[4munderlined text\x1b[24m.\n"
        L"\x1b[9mStrikethrough text\x1b[29m and \x1b[7mreverse video\x1b[27m.\n"
        L"24-bit colors: \x1b[38;2;255;100;0mOrange\x1b[0m, \x1b[48;2;0;255;255mCyan Background\x1b[0m.\n"
        L"Cursor movement:\n"
        L"Line1\n"
        L"Line2\n"
        L"\x1b[2A\x1b[10CMoved cursor up 2 lines and right 10 columns.\n"
        L"Clearing line:\n"
        L"Will clear this line.\x1b[2K\x1b[1GLine cleared and cursor moved to start.\n"
        L"End of demo. \x1b[0m";

    // Length of text (number of WCHARs)
    DWORD len = (DWORD)(sizeof(text) / sizeof(WCHAR) - 1);

    // Call write_text with cursor_persist=0
    int result = write_text(text, len, 0);
    if (result != 0) {
        wprintf(L"write_text failed\n");
    }

    FreeLibrary(hDll);
    return 0;
}