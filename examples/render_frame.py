import ctypes

# Load DLLs
wind = ctypes.WinDLL("./winD.dll")
kernel32 = ctypes.WinDLL("kernel32")

# --- Windows console types ---
CHAR = ctypes.c_wchar        # Unicode character
WORD = ctypes.c_ushort       # 16-bit unsigned short

class CHAR_INFO(ctypes.Structure):
    _fields_ = [
        ("Char", CHAR),
        ("Attributes", WORD),
    ]

# --- Console color attribute constants ---
# Foreground colors
FOREGROUND_WHITE  = 0x000F
FOREGROUND_CYAN   = 0x0003
FOREGROUND_RED    = 0x0004
FOREGROUND_BLUE   = 0x0001
FOREGROUND_YELLOW = 0x0006
FOREGROUND_GREEN  = 0x0002

# Background colors
BACKGROUND_MAGENTA = 0x0050
BACKGROUND_GREEN   = 0x0020
BACKGROUND_BLUE    = 0x0010
BACKGROUND_RED     = 0x0040
BACKGROUND_YELLOW  = 0x0060
BACKGROUND_WHITE   = 0x0070

# --- Configuration ---
ROWS, COLS = 12, 40  # Buffer dimensions

# "WinD" block letters text pattern
TEXT_PATTERN = [
    "██     ██ ██ ███    ██ ██████  ",
    "██     ██ ██ ████   ██ ██   ██ ",
    "██     ██ ██ ██ ██  ██ ██   ██ ",
    "██  █  ██ ██ ██  ██ ██ ██   ██ ",
    "██ ███ ██ ██ ██   ████ ██   ██ ",
    " ███ ███  ██ ██    ███ ██████  ",
]

START_ROW = 3  # Vertical offset for text in buffer
START_COL = 4  # Horizontal offset for text in buffer

# --- Initialize buffer ---
buffer_len = ROWS * COLS
buffer = (CHAR_INFO * buffer_len)()

# Fill buffer with spaces + blue background and white foreground
default_attr = BACKGROUND_BLUE | FOREGROUND_WHITE
for i in range(buffer_len):
    buffer[i].Char = ' '
    buffer[i].Attributes = default_attr

# Overlay text pattern with yellow background and red foreground
text_attr = BACKGROUND_YELLOW | FOREGROUND_RED
for row_offset, line in enumerate(TEXT_PATTERN):
    for col_offset, ch in enumerate(line):
        y = START_ROW + row_offset
        x = START_COL + col_offset
        if 0 <= y < ROWS and 0 <= x < COLS:
            idx = y * COLS + x
            buffer[idx].Char = ch
            buffer[idx].Attributes = text_attr

# --- Define function prototype ---
wind.render_frame.argtypes = [
    ctypes.POINTER(CHAR_INFO),  # Pointer to buffer
    ctypes.c_uint32,            # Buffer length (DWORD)
    ctypes.c_short,             # Rows (SHORT)
    ctypes.c_short,             # Columns (SHORT)
    ctypes.c_short,             # X offset on screen (SHORT)
    ctypes.c_short,             # Y offset on screen (SHORT)
]
wind.render_frame.restype = ctypes.c_int

# --- Render the frame ---
offset_x, offset_y = 95, 30

result = wind.render_frame(buffer, buffer_len, ROWS, COLS, offset_x, offset_y)

# Error handling
if result == -1:
    error_code = kernel32.GetLastError()
    print(f"render_frame failed with error code: {error_code}")