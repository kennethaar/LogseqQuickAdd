;------------------------------------------------------------------------------
;                           Logseq-Quickadd
;
; A way to easily capture your clipboard or anything you would like to Logseq.
;
; Features:
; - ✓ Adds to you daily journal With CTRL+ALT+L
; - ✓ Asks for location of your Journals folder on first run.
; - ✓ Switches to Logseq after capturing
;
; Future features
; - Configurable hotkey
; - Choose if you want to switch to Logseq after capturing or not.
;
;                       Created by Kenneth Aar
;------------------------------------------------------------------------------
;SETTINGS
;------------------------------------------------------------------------------
#Requires AutoHotkey v2.0+
#SingleInstance force

;------------------------------------------------------------------------------
;Icon Tip
;------------------------------------------------------------------------------
A_IconTip := "LOGSEQ QUICKADD`nPress SHIFT+CTRL+L to add`nyour clipboard as task to Logseq"

;------------------------------------------------------------------------------
; Add ICON to your tray. REMEMBER to put an ICO file in same folder as the script.
;------------------------------------------------------------------------------
TraySetIcon(A_ScriptDir "\Icon-Logseq.ico")

;------------------------------------------------------------------------------
; Check if INI file exists with path to folder where you want to add TODOs
;------------------------------------------------------------------------------
iniPath := A_ScriptDir "\LogseqQuickAdd.ini"

if !IniRead(iniPath, "General", "CustomPath", 0)
{
; Warning and dialog for choosing folder
    MsgBox "Choose the folder where your journal files are.", "LOGSEQ QUICKADD"
  if !customDir := DirSelect()
; Warning that no folder is selected
    MsgBox "You have to select journalfolder for script to work.", "Error - Logseq Quick Add"
    ;~ ExitApp

  IniWrite(customDir, iniPath, "General", "CustomPath")
}
customDir := IniRead(iniPath, "General", "CustomPath")

; If the folder is selected show welcome message
If IniRead(iniPath, "General", "CustomPath", 0)
TrayTip "Capturing to: " customDir "`nCapture to Logseq by pressing CTRL+Shift+L", "Logseg Quick Add"

;-----------------------------------------------------------------------------
; Trigger (Shift + Ctrl + L)
+^l:: ;LOGSEQ QuickAdd

;------------------------------------------------------------------------------
; Path to Logseq inbox
;------------------------------------------------------------------------------
CaptureFilePath := customDir "\" A_YYYY "_" A_MM "_" A_DD ".md"


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
;------------------------------------------------------------------------------

Try FileAppend("`n- TODO " UserInput " `n", CaptureFilePath)
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
