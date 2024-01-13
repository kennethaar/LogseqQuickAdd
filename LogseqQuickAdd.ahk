;------------------------------------------------------------------------------
;                           LogseqQuickadd
;
; A way to easily capture your clipboard or anything you would like to Logseq.
;
; Features:
; - ✓ Adds clipboard + text to your daily journal as a TODO with CTRL+ALT+L
; - ✓ Asks for location of your Journals folder on first run.
; - ✓ Switches to Logseq after capturing
;
; Future features
; - Configurable hotkey
; - Configurable if items should be TODO
; - Possible to assign contexts
; - Choose if you want to switch to Logseq after capturing or not.
;
;                       Created by Kenneth Aar
;
;------------------------------------------------------------------------------
;SETTINGS
;------------------------------------------------------------------------------
#Requires AutoHotkey v2.0+
#SingleInstance force
VarScriptName := "LogseqQuickAdd"
VarVersionNo := "v010"

;------------------------------------------------------------------------------
;Icon Tip
;------------------------------------------------------------------------------
A_IconTip := VarScriptName " " VarVersionNo "`nPress SHIFT+CTRL+L to add`nyour clipboard as task to Logseq"

;------------------------------------------------------------------------------
; Add ICON to your tray. REMEMBER to put an ICO file in same folder as the script.
;------------------------------------------------------------------------------
Try TraySetIcon(A_ScriptDir "\" VarScriptName ".ico")
Catch
TrayTip "Remember to add " VarScriptName ".ico to same folder as " VarScriptName ".ahk", VarScriptName

;------------------------------------------------------------------------------
; Check if INI file exists with path to folder where you want to add TODOs
;------------------------------------------------------------------------------
iniPath := A_ScriptDir "\" VarScriptName ".ini"
if !IniRead(iniPath, "General", "CustomPath", 0)
{
; Dialog for choosing folder
    MsgBox "Choose the folder where your journal files are.", VarScriptName " " VarVersionNo
  if !customDir := DirSelect()
; Warning that no folder is selected
    MsgBox "You have to select journalfolder for script to work.", "Error -" VarScriptName " " VarVersionNo
    ;~ ExitApp

  IniWrite(customDir, iniPath, "General", "CustomPath")
}
customDir := IniRead(iniPath, "General", "CustomPath")

; If the folder is selected show welcome message
If IniRead(iniPath, "General", "CustomPath", 0)
TrayTip "Capturing to: " customDir "`nCapture to Logseq by pressing CTRL+Shift+L", VarScriptName " " VarVersionNo

;-----------------------------------------------------------------------------
; Trigger (Shift + Ctrl + L)
+^l:: ;Hotkey to launch script
{
;------------------------------------------------------------------------------
; Path to Logseq Journals folder
;------------------------------------------------------------------------------
CaptureFilePath := customDir "\" A_YYYY "_" A_MM "_" A_DD ".md"

;------------------------------------------------------------------------------
; Launch inputbox
;------------------------------------------------------------------------------
IB := InputBox("Add a task to your journal`n`nWill be added to the bottom of your daily Journal page.", VarScriptName " " VarVersionNo , "w400 h150", A_Clipboard)
; If you canceled show what you entered in a msgbox
if IB.Result = "Cancel"
    TrayTip "You entered '" IB.Value "' but then cancelled." , VarScriptName " " VarVersionNo  , 1
    ; If you clicked OK, send what you entered to variable and continue with the rest of the script.
    else
       UserInput := IB.Value

;------------------------------------------------------------------------------
; Append input from inputbox to Logseq journals file
;------------------------------------------------------------------------------
Try FileAppend("`n- TODO " UserInput " `n", CaptureFilePath)
Catch
TrayTip
(
"Tried to add your input to Logseq but couldn't. Either could not find file or no input"
) , VarScriptName " " VarVersionNo  , 1
Sleep 1000

;------------------------------------------------------------------------------
;~ Switches to Logseq.
;------------------------------------------------------------------------------
Try WinActivate "ahk_exe Logseq.exe"
Catch
TrayTip
(
"Logseq is not started"
) , VarScriptName " " VarVersionNo , 1
Return
}
