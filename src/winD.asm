bits 64
default rel

extern GetStdHandle
extern WriteConsoleOutputW
extern GetLastError

section .text
global render_frame

%define STD_OUTPUT_HANDLE -11
%define INVALID_HANDLE_VALUE -1

; -----------------------------------------------------------------------------
; void render_frame(CHAR_INFO* buffer, DWORD length, SHORT rows, SHORT cols)
;
; Parameters:
;   rcx = pointer to CHAR_INFO array (buffer to write)
;   rdx = length of the buffer
;   r8  = rows (number of rows in the buffer)
;   r9  = cols (number of columns in the buffer)
;
; Description:
;   This function writes a rectangular buffer of character and attribute data
;   to the Windows console screen buffer using WriteConsoleOutputW.
; -----------------------------------------------------------------------------
render_frame:
    push rbp
    mov rbp, rsp

    ; Shadow space for GetStdHandle + WriteConsoleOutputW
    sub rsp, 96

    ; ---------------------------
    ; Verify rows*cols <= length
    ; ---------------------------
    mov rax, r8
    imul rax, r9
    cmp rax, rdx
    ja .error_handle

    mov r11, rcx ; Preserve CHAR_INFO* 

    ; ---------------------------
    ; Call GetStdHandle(STD_OUTPUT_HANDLE)
    ; ---------------------------
    mov ecx, STD_OUTPUT_HANDLE
    call GetStdHandle

    ; ---------------------------
    ; Invalid handle
    ; ---------------------------
    cmp rax, INVALID_HANDLE_VALUE
    je .error_handle

    mov r10, rax ; Preserve handle

    ; ---------------------------
    ; Prepare COORD structure (dwBufferSize)
    ; COORD: 2 SHORTs (X, Y) representing buffer dimensions
    ; Stored at [rsp]
    ; ---------------------------
    mov word [rsp], r9w   ; cols
    mov word [rsp+2], r8w ; rows

    ; ---------------------------
    ; Prepare SMALL_RECT structure (lpWriteRegion)
    ; SMALL_RECT: 4 SHORTs (Left, Top, Right, Bottom) defining region to write
    ; Left and Top are zero (start at top-left of screen)
    ; Right = cols - 1, Bottom = rows - 1 (zero-based indices)
    ; Stored at [rsp+4]
    ; ---------------------------
    mov word [rsp+4], 0 ; Left = 0
    mov word [rsp+6], 0 ; Top = 0
    mov ax, r9w
    dec ax
    mov word [rsp+8], ax ; Right = cols - 1
    mov ax, r8w
    dec ax
    mov word [rsp+10], ax ; Bottom = rows - 1

    ; ---------------------------
    ; Set up registers for WriteConsoleOutputW call
    ;   rcx = hConsoleOutput (handle)
    ;   rdx = lpBuffer (pointer to CHAR_INFO array)
    ;   r8  = dwBufferSize (pointer to COORD)
    ;   r9  = dwBufferCoord (starting coord in buffer; set to 0,0)
    ;   [rsp+32] = lpWriteRegion (region to write at)
    ; ---------------------------
    mov rcx, r10     ; hConsoleOutput
    mov rdx, r11     ; lpBuffer
    lea r8, [rsp]    ; dwBufferSize
    xor r9, r9       ; dwBufferCoord
    lea rax, [rsp+4] ; lpWriteRegion
    mov [rsp+32], rax

    ; ---------------------------
    ; Call WriteConsoleOutputW()
    ; ---------------------------
    call WriteConsoleOutputW

    ; ---------------------------
    ; WinAPI error
    ; ---------------------------
    test eax, eax
    jz .error_handle

    ; ---------------------------
    ; Cleanup stack and restore frame pointer
    ; ---------------------------
    add rsp, 96 ; reset shadow space
    pop rbp
    
    xor eax, eax ; 0 - successful
ret

.error_handle:
    ; ---------------------------
    ; Store windows error code on failure
    ; ---------------------------
    call GetLastError

    ; ---------------------------
    ; Cleanup stack and restore frame pointer
    ; ---------------------------
    add rsp, 96 ; reset shadow space
    pop rbp
ret