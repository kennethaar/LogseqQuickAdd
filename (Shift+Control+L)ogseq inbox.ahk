;------------------------------------------------------------------------------
;SETTINGS
;------------------------------------------------------------------------------
#Requires AutoHotkey v2.0+
#SingleInstance force
;--
;Icon Tip
;--

A_IconTip := "LOGSEQ QUICKADD`nPress SHIFT+CTRL+L to add`nyour clipboard as task to Logseq"

;------------------------------------------------------------------------------
; Add ICON to your tray. REMEMBER to put an ICO file in same folder as the script.

;------------------------------------------------------------------------------

TraySetIcon("Icon-Logseq.ico")

;------------------------------------------------------------------------------
; Define hotkey trigger

;------------------------------------------------------------------------------

; Trigger (Shift + Ctrl + L)
+^l:: ;LOGSEQ QuickAdd To change the letter just pick you own letter after `+^`

;------------------------------------------------------------------------------
; Path to Logseq inbox
; CHANGE THE PATH BELOW to reflect the path the file you want to add to
;------------------------------------------------------------------------------
{
; Use the line below(remove the semicolon) if you want to add to your currrent journals page. WILL NOT WORK UNLESS your journals page uses YYYY_MM_DD for example: 2024_01_01 format as date.
;InboxFilePath := "C:\Users\YOURUSERNAME\Documents\Logseq\Graphname\journals\" A_YYYY "_" A_MM "_" A_DD ".md"

; Use the line below if you want to add to your inbox.md page
; InboxFilePath := "C:\Users\YOURUSERNAME\Documents\Logseq\Graphname\pages\Inbox.md"


;------------------------------------------------------------------------------
; Launch inputbox
;------------------------------------------------------------------------------
IB := InputBox("Add a task to your journal`n`nWill be added to the bottom of your daily Journal page.", "Logseq QuickAdd", "w400 h150", A_Clipboard)
; If you canceled show what you entered in a msgbox
if IB.Result = "Cancel"
    TrayTip "You entered '" IB.Value "' but then cancelled." ,"LOGSEQ QUICKADD", 1
; If you clicked OK, send what you entered to variable and continue with the rest of the script.
else
   UserInput := IB.Value

;------------------------------------------------------------------------------
; Append input from inputbox to Logseq inbox file
; Predended with "- TODO" and appended with todays date
;------------------------------------------------------------------------------
; The line below adds date to the end of your block
; Try FileAppend("`n- TODO " UserInput " [[" A_YYYY "-" A_MM "-" A_DD "]] `n", InboxFilePath)
; The line below just adds your clipboard to your bloc
Try FileAppend("`n- TODO " UserInput " `n", InboxFilePath)
Catch
TrayTip
(
"Tried to add your input to Logseq but couldn't. Either could not find file or no input"
) ,"LOGSEQ QUICKADD", 1

Sleep 1000

;~ Switches to Logseq.
Try WinActivate "ahk_exe Logseq.exe"
Catch
TrayTip
(
"Logseq is not started"
) ,"LOGSEQ QUICKADD", 1
Return
}
