# CaptureToLogseq
AutoHotKey script to capture to Logseq

![image](https://github.com/kennethaar/CaptureToLogseq/assets/5931199/5e9b1646-1665-437a-8862-35bc58ed805a)

## Requirements:
- Windows
- AutoHotKey

## How to setup

Install the open source scripting language AutoHotKey first. http://autohotkey.com

Place the .AHK file and .ico file in your desired folder. Double click to start the script.

Pressing Shift + Ctrl + L will open the window and add you clipboardcontents or what you write to your journals file.

## Settings

The Trigger is `Shift + Ctrl + L`. To change the letter just pick you own letter after `+^`

### Default text

Remove `% clipboard` from the line starting with `InputBox` to stop the script from adding you clippboard as default text

Remove `TODO` from the line starting with `FileAppend` to not make new items a task


