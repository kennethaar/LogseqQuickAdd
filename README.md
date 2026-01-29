# LogseqQuickAdd
AutoHotKey script to capture to Logseq.

A way to easily capture your clipboard or anything you would like to Logseq.

## Features:
- Adds to you daily journal With CTRL+ALT+L
- Asks for location of your Journals folder on first run.
- Scans for your contextsa in logseg (Specify what  your contexts namespace is and LogseqQuickAdd will add the automatically)
- Optionally switches to Logseq after capturing
- First line becomes the task text. Additional lines become sub-blocks

## Screenshots

Your clipboard is added as default text. 
<img width="777" height="843" alt="image" src="https://github.com/user-attachments/assets/58cc0af6-c62f-4172-ab20-0648e2304409" />

How It looks in Logseq:
<img width="746" height="131" alt="image" src="https://github.com/user-attachments/assets/a45919e8-7b66-49e4-ac78-a4a1be5948cb" />


## Requirements:
- Windows
- AutoHotKey

## How to setup

Install the open source scripting language AutoHotKey first. http://autohotkey.com

Place the .AHK file and .ico file in your desired folder. Double click to start the script.

To automatically run on startup add to your startupfolder.

Pressing Shift + Ctrl + L will open the window and add you clipboardcontents or what you write to your journals file.

## Settings

The script can be edited, right click and choose edit.

The Trigger is `Shift + Ctrl + L`. To change the letter just pick you own letter after `+^`


