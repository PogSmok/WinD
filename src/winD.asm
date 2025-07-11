bits 64
default rel

extern GetStdHandle
extern WriteConsoleOutputW
extern GetConsoleScreenBufferInfo
extern GetConsoleMode
extern SetConsoleMode
extern WriteConsoleW
extern SetConsoleCursorPosition
extern PlaySoundW

; As for Windows documentation
%define STD_OUTPUT_HANDLE                  0xFFFFFFF5
%define ENABLE_VIRTUAL_TERMINAL_PROCESSING 0x0004
%define INVALID_HANDLE_VALUE               0xFFFFFFFFFFFFFFFF
%define SND_FILENAME                       0x00020000
%define SND_ASYNC                          0x00000001
%define PLAY_FLAGS                         SND_FILENAME | SND_ASYNC

; ==== SECTION BSS =====
section .bss
render_handle resq 1 ; store gathered handle for render_frame
write_handle  resq 1 ; store gathered handle for write_text

; ===== SECTION TEXT =====
section .text   

align 16

global render_frame
global write_text   
global play_audio
global stop_audio

; -----------------------------------------------------------------------------
; void render_frame(CHAR_INFO* buffer, DWORD length, SHORT rows, SHORT cols, SHORT offset_x, SHORT offset_y)
;
; Parameters:
;   RCX      = buffer (pointer to CHAR_INFO array)
;   EDX      = length (buffer length)
;   R8W      = rows (number of rows in the buffer)
;   R9W      = cols (number of columns in the buffer)
;   [rbp+48] = offset_x (horizontal offset where to start writing in the console screen buffer)
;   [rbp+56] = offset_y (vertical offset where to start writing in the console screen buffer)
;
; Returns:
;   RAX = 0 on success, -1 on failure
;
; Description:
;   Writes a rectangular buffer of character and attribute data to the Windows console
;   screen buffer using WriteConsoleOutputW, starting at the specified (offset_x, offset_y)
;   position in the console screen buffer. 
;   On failure, to extract specific Windows error code call GetLastError.
; -----------------------------------------------------------------------------
render_frame:
    ; set up stack frame
    push    rbp
    mov     rbp, rsp

    ; 32 bytes of shadow space + 8 bytes for SMALL_RECT
    sub     rsp, 40

    ; preserve non-volatile registers
    push    r12
    push    r13
    push    r14

    mov     r12, rcx                 ; preserve CHAR_INFO* 
    mov     r13, [rel render_handle] ; move cached handle into register
    ; ---------------------------
    ; Prepare COORD structure (dwBufferSize)
    ; COORD: 2 SHORTs (X, Y) representing buffer dimensions
    ; ---------------------------
    mov     r14w, r8w
    shl     r14d, 16
    mov     r14w, r9w

    ; check if handle is cached
    test    r13, r13
    jnz     .render_ok 

    ; ---------------------------
    ; Call GetStdHandle(STD_OUTPUT_HANDLE)
    ; ---------------------------
    mov     ecx, STD_OUTPUT_HANDLE
    call    GetStdHandle
    cmp     rax, INVALID_HANDLE_VALUE
    je      .render_error

    ; preserve STD_OUTPUT_HANDLE handle
    mov     r13, rax
    mov     [rel render_handle], r13

.render_ok:
    ; ---------------------------
    ; Load offset parameters from stack
    ; ---------------------------
    mov     cx, word [rbp+48]  ; offset_x
    mov     dx, word [rbp+56]  ; offset_y

    ; ---------------------------
    ; Prepare SMALL_RECT structure (lpWriteRegion)
    ; SMALL_RECT: 4 SHORTs (Left, Top, Right, Bottom) defining region to write
    ; Left = offset_x, Top = offset_y
    ; Right = cols - 1, Bottom = rows - 1 (zero-based indices)
    ; Stored at [rsp]
    ; ---------------------------
    mov     word [rsp], cx   ; Left = offset_x
    mov     word [rsp+2], dx ; Top = offset_y

    ; Calculate Right = offset_x + cols - 1
    mov     ax, r14w
    add     ax, cx         
    dec     ax            
    mov     word [rsp+4], ax ; Right = offset_x + cols - 1

    ; Calculate Bottom = offset_y + rows - 1
    mov     eax, r14d
    shr     eax, 16          ; rows is upper 16 bits of r14d
    mov     ax, dx       
    add     ax, r14w   
    dec     ax                 
    mov     word [rsp+6], ax ; Bottom = offset_y + rows - 1

    ; ---------------------------
    ; Call WriteConsoleOutputW(STD_OUTPUT_HANDLE, buffer, length, NULL, lpWriteRegion)
    ; ---------------------------
    mov     rcx, r13      ; hConsoleOutput
    mov     rdx, r12      ; lpBuffer
    mov     r8d, r14d     ; dwBufferSize
    xor     r9, r9        ; dwBufferCoord
    mov     [rsp+32], rsp ; lpWriteRegion
    call    WriteConsoleOutputW
    test    eax, eax
    jz      .render_error

    ; restore non-volatile registers
    pop     r14
    pop     r13
    pop     r12

    add     rsp, 40 ; restore shadow space
    pop     rbp     ; restore stack frame
    
    mov eax, eax ; 0 - successful
    ret

.render_error:
    ; restore non-volatile registers
    pop     r14
    pop     r13
    pop     r12

    add     rsp, 40 ; restore shadow space
    pop     rbp     ; restore stack frame

    or      eax, 0xFFFFFFFF ; return -1 (failure)
    ret

; -----------------------------------------------------------------------------
; int write_text(WCHAR* buffer, DWORD len, CHAR cursor_persist)
;
; Parameters:
;   RCX = buffer (pointer to UTF-16 string)
;   EDX = len (string length)
;   R8B = cursor_persist (0 = reset cursor position)
;
; Returns:
;   RAX = 0 on success, -1 on failure
;
; Description:
;   Enables Virtual Terminal Processing (VT) on the console output,
;   allowing ANSI escape sequences (e.g., for 24-bit RGB color),
;   and then writes the UTF-16 string to the console using WriteConsoleW.
;   On failure, to extract specific Windows error code call GetLastError.
; -----------------------------------------------------------------------------
write_text:
    ; 32 bytes of shadow space + 28 bytes for CONSOLE_SCREEN_BUFFER_INFO + 4 bytes for lpMode
    sub     rsp, 64

    ; preserve non-volatile registers
    push    r12
    push    r13
    push    r14

    mov     r12,  rcx               ; preserve pointer to string
    mov     r13d, edx               ; preserve lenght of string
    mov     r14, [rel write_handle] ; move cached handle into register

    ; branch immediately to avoid storing preserve_cursor   
    test    r8b, r8b
    jz      .no_info

    ; check if handle is cached
    test    r14, r14
    jnz     .cache_info_ok   

    ; ---------------------------
    ; Call GetStdHandle(STD_OUTPUT_HANDLE)
    ; ---------------------------
    mov     ecx, STD_OUTPUT_HANDLE
    call    GetStdHandle
    cmp     rax, INVALID_HANDLE_VALUE
    je      .write_error

    ; preserve STD_OUTPUT_HANDLE handle
    mov     r14, rax
    mov     [rel write_handle], r14

    ; ---------------------------
    ; Call GetConsoleMode(STD_OUTPUT_HANDLE, lpMode*)
    ; ---------------------------
    mov     rcx, r14       ; STD_OUTPUT_HANDLE
    lea     rdx, [rsp+28]  ; pointer to lpMode
    call    GetConsoleMode 
    test    eax, eax
    jz      .write_error

    ; Check if virtual terminal is set
    mov     edx, dword [rsp+28]
    test    edx, ENABLE_VIRTUAL_TERMINAL_PROCESSING
    jnz     .cache_info_ok

    ; ---------------------------
    ; Call SetConsoleMode(STD_OUTPUT_HANDLE, lpMode | ENABLE_VIRTUAL_TERMINAL_PROCESSING)
    ; ---------------------------
    mov     rcx, r14 ; STD_OUTPUT_HANDLE
    ; mov   edx, dword [rsp+28] (done before)
    or      edx, ENABLE_VIRTUAL_TERMINAL_PROCESSING
    call    SetConsoleMode
    test    eax, eax
    jz      .write_error

.cache_info_ok:
    ; ---------------------------
    ; Call GetConsoleScreenBufferInfo(STD_OUTPUT_HANDLE, CONSOLE_SCREEN_BUFFER_INFO*)
    ; ---------------------------
    mov     rcx, r14   ; STD_OUTPUT_HANDLE
    lea     rdx, [rsp] ; pointer to CONSOLE_SCREEN_BUFFER_INFO
    call    GetConsoleScreenBufferInfo
    test    eax, eax
    jz      .write_error

    ; ---------------------------
    ; Call WriteConsoleW(STD_OUTPUT_HANDLE, buffer, len, NULL)
    ; ---------------------------
    mov     rcx, r14  ; STD_OUTPUT_HANDLE
    mov     rdx, r12  ; buffer
    mov     r8d, r13d ; len
    xor     r9, r9    ; NULL
    call    WriteConsoleW

    ; ---------------------------
    ; Call SetConsoleCursorPosition(STD_OUTPUT_HANDLE, COORD)
    ; ---------------------------
    mov     rcx, r14 ; STD_OUTPUT_HANDLE
    ; EDX: 2 most significant bytes - Y coordinate
    ; EDX: 2 least significant bytes - X coordinate
    mov     edx, dword [rsp+4] ; COORDS are offset by 4 bytes
    call    SetConsoleCursorPosition
    test    eax, eax
    jz      .write_error

    ; restore non-volatile registers
    pop     r14
    pop     r13
    pop     r12

    add     rsp, 64 ; restore shadow space

    xor     eax, eax ; return 0 (success)
    ret


.no_info:
    ; check if handle is cached
    test    r14, r14
    jnz     .cache_ok   

    ; ---------------------------
    ; Call GetStdHandle(STD_OUTPUT_HANDLE)
    ; ---------------------------
    mov     ecx, STD_OUTPUT_HANDLE
    call    GetStdHandle
    cmp     rax, INVALID_HANDLE_VALUE
    je      .write_error

    ; preserve STD_OUTPUT_HANDLE handle
    mov     r14, rax
    mov     [rel write_handle], r14

    ; ---------------------------
    ; Call GetConsoleMode(STD_OUTPUT_HANDLE, lpMode*)
    ; ---------------------------
    mov     rcx, r14       ; STD_OUTPUT_HANDLE
    lea     rdx, [rsp+28]  ; pointer to lpMode
    call    GetConsoleMode 
    test    eax, eax
    jz      .write_error

    ; Check if virtual terminal is set
    mov     edx, dword [rsp+28]
    test    edx, ENABLE_VIRTUAL_TERMINAL_PROCESSING
    jnz     .cache_ok

    ; ---------------------------
    ; Call SetConsoleMode(STD_OUTPUT_HANDLE, lpMode | ENABLE_VIRTUAL_TERMINAL_PROCESSING)
    ; ---------------------------
    mov     rcx, r14   ; STD_OUTPUT_HANDLE
    ; mov   edx, dword [rsp+28] (done before)
    or      edx, ENABLE_VIRTUAL_TERMINAL_PROCESSING
    call    SetConsoleMode
    test    eax, eax
    jz      .write_error

.cache_ok:
    ; ---------------------------
    ; Call WriteConsoleW(STD_OUTPUT_HANDLE, buffer, len, NULL)
    ; ---------------------------
    mov     rcx, r14  ; STD_OUTPUT_HANDLE
    mov     rdx, r12  ; buffer
    mov     r8d, r13d ; len
    xor     r9, r9    ; NULL
    call    WriteConsoleW
    test    eax, eax
    jz      .write_error

    ; restore non-volatile registers
    pop     r14
    pop     r13
    pop     r12

    add     rsp, 64 ; restore shadow space

    xor     eax, eax ; return 0 (success)
    ret

.write_error:
    ; restore non-volatile registers
    pop     r14
    pop     r13
    pop     r12

    add     rsp, 64 ; restore shadow space

    or      eax, 0xFFFFFFFF ; return -1 (failure)
    ret


; -----------------------------------------------------------------------------
; int play_audio(LPCWSTR soundFilePath)
;
; Parameters:
;   RCX = pointer to wide string (LPCWSTR) containing the sound file path
;
; Returns:
;   RAX = 0 on success, -1 on failure
;
; Description:
;   Plays the specified sound asynchronously using PlaySoundW with flags
;   SND_FILENAME | SND_ASYNC. Returns 0 on success, non-zero on failure.
;   On failure, to extract specific Windows error code call GetLastError.
; -----------------------------------------------------------------------------
play_audio:
    sub     rsp, 32 ; 32 bytes of shadow space

    ; ---------------------------
    ; Call PlaySoundW(soundFilePath, NULL, SND_FILENAME | SND_ASYNC)
    ; ---------------------------
    xor     rdx, rdx        ; hmod = NULL
    mov     r8d, PLAY_FLAGS ; SND_FILENAME | SND_ASYNC
    call    PlaySoundW

    ; restore before jump to decrease branch size
    add     rsp, 32 ; restore shadow space

    test    eax, eax
    jnz     audio_error

    xor     eax, eax ; 0 - successful
    ret

; -----------------------------------------------------------------------------
; int stop_audio()
;
; Returns:
;   RAX = 0 on success, -1 on failure
;
; Description:
;   Stops any currently playing sound using PlaySoundW with NULL parameters.
;   Returns 0 on success, non-zero on failure.
;   On failure, to extract specific Windows error code call GetLastError.
; -----------------------------------------------------------------------------
stop_audio:
    sub     rsp, 32 ; 32 bytes of shadow space

    ; ---------------------------
    ; Call PlaySoundW(NULL, NULL, NULL)
    ; ---------------------------
    xor     rcx, rcx
    xor     rdx, rdx
    xor     r8, r8
    call    PlaySoundW

    ; restore before jump to decrease branch size
    add     rsp, 32 ; restore shadow space

    test    eax, eax
    jnz     audio_error

    xor     eax, eax ; 0 - successful 
    ret 

audio_error:
    or      eax, 0xFFFFFFFF ; return -1 (failure)
    ret
