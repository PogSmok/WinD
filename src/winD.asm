bits 64
default rel

extern GetStdHandle
extern WriteConsoleOutputW
extern PlaySoundW
extern GetLastError

section .text
global render_frame
global play_audio
global stop_audio

%define STD_OUTPUT_HANDLE -11
%define INVALID_HANDLE_VALUE -1

; -----------------------------------------------------------------------------
; void render_frame(CHAR_INFO* buffer, DWORD length, SHORT rows, SHORT cols, SHORT offset_x, SHORT offset_y)
;
; Parameters:
;   rcx = pointer to CHAR_INFO array (buffer to write)
;   rdx = length of the buffer
;   r8  = rows (number of rows in the buffer)
;   r9  = cols (number of columns in the buffer)
;   [rsp+32] = offset_x (horizontal offset where to start writing in the console screen buffer)
;   [rsp+40] = offset_y (vertical offset where to start writing in the console screen buffer)
;
; The original RSP is at RBP + 8, so:
;   - offset_x is at [RBP + 8 + 40] = [RBP + 48]
;   - offset_y is at [RBP + 8 + 48] = [RBP + 56]
;
; Description:
;   Writes a rectangular buffer of character and attribute data to the Windows console
;   screen buffer using WriteConsoleOutputW, starting at the specified (offset_x, offset_y)
;   position in the console screen buffer. 
; -----------------------------------------------------------------------------
render_frame:
    push rbp
    mov rbp, rsp

    ; Shadow space for GetStdHandle + WriteConsoleOutputW + GetLastError
    sub rsp, 96

    ; ---------------------------
    ; Verify rows*cols <= length
    ; ---------------------------
    mov rax, r8
    imul rax, r9
    cmp rax, rdx
    ja error_handle_render

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
    je  error_handle_render

    mov r10, rax ; Preserve handle

    ; ---------------------------
    ; Prepare COORD structure (dwBufferSize)
    ; COORD: 2 SHORTs (X, Y) representing buffer dimensions
    ; Stored at [rsp]
    ; ---------------------------
    mov word [rsp], r9w   ; cols
    mov word [rsp+2], r8w ; rows
    

    ; ---------------------------
    ; Load offset parameters from stack
    ; ---------------------------
    mov cx, word [rbp+48]  ; offset_x
    mov dx, word [rbp+56]  ; offset_y

    ; ---------------------------
    ; Prepare SMALL_RECT structure (lpWriteRegion)
    ; SMALL_RECT: 4 SHORTs (Left, Top, Right, Bottom) defining region to write
    ; Left = offset_x, Top = offset_y
    ; Right = cols - 1, Bottom = rows - 1 (zero-based indices)
    ; Stored at [rsp+8]
    ; ---------------------------
    mov word [rsp+4], cx ; Left = offset_x
    mov word [rsp+6], dx ; Top = offset_y

    ; Calculate Right = offset_x + cols - 1
    mov ax, cx          
    add ax, r9w           
    dec ax            
    mov word [rsp+8], ax     ; Right = offset_x + cols - 1
    
    ; Calculate Bottom = offset_y + rows - 1
    mov ax, dx       
    add ax, r8w   
    dec ax                 
    mov word [rsp+10], ax     ; Bottom = offset_y + rows - 1

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
    mov r8d, [rsp]   ; dwBufferSize
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
    jz error_handle_render

    ; ---------------------------
    ; Cleanup stack and restore frame pointer
    ; ---------------------------
    add rsp, 96 ; reset shadow space
    pop rbp
    
    xor eax, eax ; 0 - successful
ret

error_handle_render:
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

; -----------------------------------------------------------------------------
; int play_audio(LPCWSTR soundFilePath)
;
; Parameters:
;   rcx = pointer to wide string (LPCWSTR) containing the sound file path
;
; Description:
;   Plays the specified sound asynchronously using PlaySoundW with flags
;   SND_FILENAME | SND_ASYNC. Returns 0 on success, non-zero on failure.
; -----------------------------------------------------------------------------
play_audio:
    push rbp
    mov rbp, rsp

    sub rsp, 32

    xor rdx, rdx        ; hmod = NULL
    mov r8d, 0x00020001 ; SND_FILENAME | SND_ASYNC

    call PlaySoundW

    ; ---------------------------
    ; WinAPI error
    ; ---------------------------
    test eax, eax
    jnz error_handle_audio

    ; ---------------------------
    ; Cleanup stack and restore frame pointer
    ; ---------------------------
    add rsp, 32
    pop rbp

    xor eax, eax ; 0 - successful
ret

; -----------------------------------------------------------------------------
; int stop_audio()
;
; Description:
;   Stops any currently playing sound using PlaySoundW with NULL parameters.
;   Returns 0 on success, non-zero on failure.
; -----------------------------------------------------------------------------
stop_audio:
    push rbp

    sub rsp, 32

    ; ---------------------------
    ; Set all parameters to NULL
    ; ---------------------------
    xor rcx, rcx
    xor rdx, rdx
    xor r8, r8
    call PlaySoundW

    ; ---------------------------
    ; WinAPI error
    ; ---------------------------
    test eax, eax
    jnz  error_handle_audio

    ; ---------------------------
    ; Cleanup stack and restore frame pointer
    ; ---------------------------
    add rsp, 32
    pop rbp

    xor eax, eax ; 0 - successful 
ret 

error_handle_audio:
    ; ---------------------------
    ; Store windows error code on failure
    ; ---------------------------
    call GetLastError

    ; ---------------------------
    ; Cleanup stack and restore frame pointer
    ; ---------------------------
    add rsp, 32 ; reset shadow space
    pop rbp
ret
