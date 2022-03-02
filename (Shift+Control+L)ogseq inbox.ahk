;------------------------------------------------------------------------------
;SETTINGS
;------------------------------------------------------------------------------
FileEncoding, UTF-8
#NoEnv  ; Recommended for performance and compatibility with future AutoHotkey releases.
; #Warn  ; Enable warnings to assist with detecting common errors.
SendMode Input  ; Recommended for new scripts due to its superior speed and reliability.
SetWorkingDir %A_ScriptDir%  ; Ensures a consistent starting directory.
#SingleInstance force

;------------------------------------------------------------------------------
; Add ICON to your tray. REMEMBER to put an ICO file in same folder as the script.

Menu, Tray, Icon, Icon-Logseq.ico

;------------------------------------------------------------------------------
; AutoHotKey syntax
;------------------------------------------------------------------------------

; Alt = !
; Ctrl = ^
; Shift = +
; WinActivate = #
; Space {Space}
; Enter {Enter}
; Tab {Tab}
; Ignore everything after this character ;
; Escape one of the above characters `
;------------------------------------------------------------------------------
; Set you trigger. Default is Shift + Ctrl + L
;------------------------------------------------------------------------------

+^l::

;------------------------------------------------------------------------------
;~ Change the path below to reflect the path to your inbox file
;------------------------------------------------------------------------------

InboxFilePath = C:\Users\yourusername\Google Drive\Inbox.md

;------------------------------------------------------------------------------
;~ Script
;~
;~ This will trigger a userinput window. Add the contents of your clipboard as 
;~ default text, and add the todo state and date tag so it show up in you daily
;~ journal page.
;------------------------------------------------------------------------------

InputBox, UserInput, Logseq Inbox, Add task to Logseq Inbox, , 400, 150,,,,, % clipboard
FileAppend, - TODO %UserInput% [[%A_YYYY%-%A_MM%-%A_DD%]] `n, %InboxFilePath%, 

Return
