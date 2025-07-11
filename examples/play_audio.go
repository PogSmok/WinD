package main

import (
    "fmt"
    "syscall"
    "time"
    "unsafe"
)

func main() {
    // Load winD dll
    wind, err := syscall.LoadDLL("./winD.dll")
    if err != nil {
        panic(err)
    }
    defer wind.Release() // Ensure DLL resources are freed when main exits

    // Find the address of the play_audio function inside the DLL
    playAudioProc, err := wind.FindProc("play_audio")
    if err != nil {
        panic(err)
    }

    // Find the address of the stop_audio function inside the DLL
    stopAudioProc, err := wind.FindProc("stop_audio")
    if err != nil {
        panic(err)
    }

    // Path to a common Windows sound file
    soundFile := `C:\Windows\Media\Windows Background.wav`

    // Convert Go string to UTF-16 pointer as expected by Windows API and DLL
    utf16SoundFile, err := syscall.UTF16PtrFromString(soundFile)
    if err != nil {
        panic(err)
    }

    // Call play_audio with the sound file path
    r1, _, _ := playAudioProc.Call(uintptr(unsafe.Pointer(utf16SoundFile)))
    if r1 != 0 {
        fmt.Println("play_audio failed")
        return
    }
    fmt.Println("Playing sound...")

    // Wait for 0.5 seconds before stopping the sound
    time.Sleep(500 * time.Millisecond)

    // Call stop_audio to stop any playing sound
    r2, _, _ := stopAudioProc.Call()
    if r2 != 0 {
        fmt.Println("stop_audio failed")
        return
    }
    fmt.Println("Sound stopped")
}