# LogseqQuickAdd
AutoHotKey script to capture to Logseq.

A way to easily capture your clipboard or anything you would like to Logseq.

Features:
- Adds to you daily journal With CTRL+ALT+L
- Asks for location of your Journals folder on first run.
- Optionally switches to Logseq after capturing
- First line becomes the task text. Additional lines become sub-blocks

Your clipboard is added as default text. After OK it adds TODO. Then it tries to switch to Logseq.

<img width="526" height="435" alt="image" src="https://github.com/user-attachments/assets/9d4a5f87-34f3-4969-9e40-8c16afe0bfff" />

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


