# CaptureToLogseq
AutoHotScript to capture to Logseq

## Requirements:

- Windows
- AutoHotKey

## How to setup

Install AutoHotKey first.
Edit file and change the path to reflect the path to your inbox.md file.
Save the file
Place the .AHK file and .ico in your desired folder. Dubble click to start the script.

Pressing Shift + Ctrl + L will open the window and add you clipboardcontents or what you write to your inbox.md file.

## Settings

The Trigger is `Shift + Ctrl + L`. To change the letter just pick you ovwn letter after `+^`

Change the path after the InbowFilePath to send the input to your inbox.md file

Remove `% clipboard` from the line starting with `InputBox` to stop the script from adding you clippboard as default text
Remove `TODO` from the line starting with `FileAppend` to not make new items a task


