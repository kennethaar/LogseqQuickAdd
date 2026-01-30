;------------------------------------------------------------------------------
;                           LogseqQuickadd
;
; A way to easily capture your clipboard or anything you would like to Logseq.
;
;
;                       Created by Kenneth Aar
;                       Modified with GUI interface
;                       Enhanced with dynamic context scanning
;                       Improved two-column layout
;                       Fixed context mapping bug
;                       Fixed number key shortcuts for context selection
;
;------------------------------------------------------------------------------
;SETTINGSa
;------------------------------------------------------------------------------
#Requires AutoHotkey v2.0+
#SingleInstance force

;------------------------------------------------------------------------------
; Global Variables - Must be declared first
;------------------------------------------------------------------------------
global VarScriptName := "LogseqQuickAdd"
global VarVersionNo := "v018"
global Varblurb := "`nPress SHIFT+CTRL+L to add`nyour clipboard as task to Logseq"
global customDir := ""
global contextNamespace := ""
global contextList := []  ; Array to store found contexts
global taskGui := ""
global taskInputHwnd := 0  ; Store the hwnd of the task input control
global contextCheckboxes := []  ; Array to store checkbox controls
global contextDisplayOrder := []  ; Array to store contexts in the order they appear in GUI
global iniPath := A_ScriptDir "\" VarScriptName ".ini"

;------------------------------------------------------------------------------
; Helper Functions - Define before using them
;------------------------------------------------------------------------------

; Function to scan the pages folder for contexts in the namespace
ScanContextsInNamespace() {
    global customDir, contextNamespace, contextList

    contextList := []  ; Clear existing list

    if (customDir = "" || contextNamespace = "") {
        return false
    }

    ; Determine the pages folder path (should be sibling to journals folder)
    ; If customDir is "C:\MyGraph\journals", pages should be "C:\MyGraph\pages"
    parentDir := ""
    SplitPath customDir, , &parentDir
    pagesDir := parentDir "\pages"

    if (!DirExist(pagesDir)) {
        MsgBox "Cannot find pages folder at: " pagesDir "`n`nMake sure your journal folder path is correct.", "Error - " VarScriptName
        return false
    }

    ; Build the search pattern for namespace files
    ; Logseq uses triple underscores for namespace separators in filenames
    ; e.g., "c/PC" becomes "c___PC.md" and "c/PC/Discord" becomes "c___PC___Discord.md"
    searchPattern := pagesDir "\" contextNamespace "___*.md"

    ; Find all matching files
    Loop Files, searchPattern
    {
        ; Extract the context name from filename
        ; e.g., "c___PC___Discord.md" -> "PC/Discord"
        fileName := A_LoopFileName

        ; Remove the .md extension first
        contextName := StrReplace(fileName, ".md", "")

        ; Remove the namespace prefix (e.g., "c___")
        ; Since we want to remove only the first occurrence, we'll use a simple approach
        prefixToRemove := contextNamespace "___"
        if (SubStr(contextName, 1, StrLen(prefixToRemove)) = prefixToRemove) {
            contextName := SubStr(contextName, StrLen(prefixToRemove) + 1)
        }

        ; Replace all remaining triple underscores with forward slashes for nested contexts
        contextName := StrReplace(contextName, "___", "/")

        ; Decode URL encoding if present (Logseq may encode special characters)
        contextName := UrlDecode(contextName)

        ; Add to list
        contextList.Push(contextName)
    }

    ; Sort contexts alphabetically
    if (contextList.Length > 0) {
        contextList := SortArray(contextList)
    }

    return contextList.Length > 0
}

; Helper function to sort array (handles nested contexts with string comparison)
SortArray(arr) {
    if (arr.Length <= 1)
        return arr

    ; Simple bubble sort for small arrays with proper string comparison
    Loop arr.Length - 1 {
        i := A_Index
        Loop arr.Length - i {
            j := A_Index + i
            ; Use StrCompare for case-insensitive comparison
            ; StrCompare returns: -1 if str1 < str2, 0 if equal, 1 if str1 > str2
            if (StrCompare(arr[i], arr[j], false) > 0) {  ; false = case-insensitive
                temp := arr[i]
                arr[i] := arr[j]
                arr[j] := temp
            }
        }
    }
    return arr
}

; Helper function to decode URL encoding
UrlDecode(str) {
    ; Replace common URL encodings
    str := StrReplace(str, "%20", " ")
    str := StrReplace(str, "%2F", "/")
    str := StrReplace(str, "%5C", "\")
    ; Add more replacements as needed
    return str
}

; Helper function to organize contexts into groups
; Returns an object with: {topLevel: [], nested: []}
OrganizeContexts(contextList) {
    result := {topLevel: [], nested: []}

    for contextName in contextList {
        if (InStr(contextName, "/")) {
            ; This is a nested context like "Consume/Read"
            result.nested.Push(contextName)
        } else {
            ; This is a top-level context
            result.topLevel.Push(contextName)
        }
    }

    return result
}

; Helper function to find an available letter shortcut for a context
; Tries first letter, then subsequent letters, then letters from after "/" in nested contexts
; Finally falls back to any available letter from the alphabet
FindAvailableLetter(contextName, usedLetters) {
    ; For nested contexts like "Consume/Read", try the part after the last "/"
    nameToCheck := contextName
    if (InStr(contextName, "/")) {
        parts := StrSplit(contextName, "/")
        nameToCheck := parts[parts.Length]  ; Get last part (e.g., "Read" from "Consume/Read")
    }
    
    ; Try each letter in the name
    Loop StrLen(nameToCheck) {
        letter := StrLower(SubStr(nameToCheck, A_Index, 1))
        ; Check if it's a letter (a-z or Norwegian) and not already used
        if (letter ~= "^[a-zæøå]$" && !usedLetters.Has(letter)) {
            return letter
        }
    }
    
    ; If nested and no letter found, also try the parent parts
    if (InStr(contextName, "/")) {
        parts := StrSplit(contextName, "/")
        Loop parts.Length - 1 {
            partName := parts[A_Index]
            Loop StrLen(partName) {
                letter := StrLower(SubStr(partName, A_Index, 1))
                if (letter ~= "^[a-zæøå]$" && !usedLetters.Has(letter)) {
                    return letter
                }
            }
        }
    }
    
    ; Fallback: try all letters in the alphabet (including Norwegian)
    allLetters := "abcefghijklmnopqrsuvxyz"  ; Excluding t, w, d (reserved for status)
    allLetters .= "æøå"  ; Add Norwegian letters
    
    Loop StrLen(allLetters) {
        letter := SubStr(allLetters, A_Index, 1)
        if (!usedLetters.Has(letter)) {
            return letter
        }
    }
    
    ; No available letter found
    return ""
}

; Function to process multiline text for Logseq
ProcessMultilineText(taskText, statusPrefix, contextSuffix) {
    ; Check if the text contains newlines
    if (InStr(taskText, "`n") || InStr(taskText, "`r")) {
        ; Split text into lines
        lines := StrSplit(taskText, "`n", "`r")

        ; First line becomes the main TODO
        firstLine := Trim(lines[1])
        result := statusPrefix . firstLine

        ; Add context right after first line (if exists)
        if (contextSuffix != "") {
            result .= "`n" . contextSuffix
        }

        ; Remaining lines become sub-blocks (indented with two spaces and "- " prefix)
        if (lines.Length > 1) {
            Loop lines.Length - 1 {
                lineIndex := A_Index + 1
                lineText := Trim(lines[lineIndex])
                if (lineText != "") {
                    result .= "`n  - " . lineText
                }
            }
        }

        return result
    } else {
        ; Single line text
        result := statusPrefix . taskText
        if (contextSuffix != "") {
            result .= "`n" . contextSuffix
        }
        return result
    }
}

; Function to save task to Logseq journal
SaveTask(openLogseq := false) {
    global taskGui, customDir, contextNamespace, contextDisplayOrder, iniPath, VarScriptName, VarVersionNo

    ; Double-check that we have the path from INI
    if (customDir = "") {
        customDir := IniRead(iniPath, "General", "CustomPath", "")
        if (customDir = "") {
            MsgBox "Cannot find the journal folder path in the INI file. Please select it again.", "Error - " VarScriptName
            if !newDir := DirSelect()
                return
            customDir := newDir
            IniWrite(customDir, iniPath, "General", "CustomPath")
        }
    }

    ; Get the submitted values
    savedValues := taskGui.Submit(false)  ; false to not destroy the GUI yet

    ; Determine the status prefix
    statusPrefix := "- "  ; Start with dash and space for Logseq tasks
    if (savedValues.TodoCheck)
        statusPrefix .= "TODO "
    else if (savedValues.WaitingCheck)
        statusPrefix .= "WAITING "
    else if (savedValues.DoingCheck)
        statusPrefix .= "DOING "

    ; Get the task text
    taskText := savedValues.TaskInput

    ; Determine context suffix (not indented, goes right after first line)
    contextSuffix := ""
    contextName := ""

    ; Check which context checkbox is selected and get the context from contextDisplayOrder
    ; which stores contexts in the same order as they appear in the GUI
    Loop contextDisplayOrder.Length {
        checkboxName := "ContextCheck" . A_Index
        if (savedValues.HasOwnProp(checkboxName) && savedValues.%checkboxName%) {
            contextName := contextDisplayOrder[A_Index]
            ; Build the full context path (namespace/context)
            contextSuffix := "context:: [[" . contextNamespace . "/" . contextName . "]]"
            break
        }
    }

    ; Process multiline text (context is added inside this function)
    processedTask := ProcessMultilineText(taskText, statusPrefix, contextSuffix)

    ; Combine everything
    finalText := processedTask . "`n- " . "`n"

    ; Path to Logseq Journals folder
    CaptureFilePath := customDir "\" A_YYYY "_" A_MM "_" A_DD ".md"

    ; Check if file exists and what its last line contains
    fileExistsAlready := FileExist(CaptureFilePath)
    shouldAddNewline := true

    if (fileExistsAlready) {
        ; Read the last few characters to check how the file ends
        Try {
            fileContent := FileRead(CaptureFilePath)
            if (fileContent != "") {
                ; If file ends with a newline, we're good to go
                if (SubStr(fileContent, -1) == "`n") {
                    shouldAddNewline := false
                }
            }
        } Catch {
            ; If we can't read the file, just be safe and add a newline
            shouldAddNewline := true
        }
    }

    ; Prepare the text to append
    if (shouldAddNewline) {
        finalText := "`n" . processedTask . "`n"
    } else {
        finalText := processedTask . "`n"
    }

    ; Append to file
    Try {
        FileAppend(finalText, CaptureFilePath)

        ; Create detailed confirmation message with path
        confirmMsg := "Task added to:`n" . CaptureFilePath
        if (contextName != "") {
            confirmMsg .= "`n`nContext: " . contextName
        }

        TrayTip confirmMsg, VarScriptName " " VarVersionNo, 1
    } Catch as err {
        MsgBox "Error writing to file: " CaptureFilePath "`n`nError: " err.Message "`n`nMake sure the path exists and is writable.", "Error - " VarScriptName
    }

    ; Destroy the GUI
    taskGui.Destroy()

    ; Open Logseq if requested
    if (openLogseq) {
        Try {
            WinActivate "ahk_exe Logseq.exe"
        } Catch {
            TrayTip "Logseq is not started", VarScriptName " " VarVersionNo, 1
        }
    }
}

; Button event handlers
SubmitButtonHandler(ctrl, *) {
    SaveTask(false)
}

SubmitAndOpenButtonHandler(ctrl, *) {
    SaveTask(true)
}

CancelButtonHandler(ctrl, *) {
    global taskGui
    taskGui.Destroy()
    TrayTip "Task creation cancelled", VarScriptName " " VarVersionNo, 1
}

; Function to show the main GUI
ShowLogseqAddGUI(clipText := "") {
    global taskGui, taskInputHwnd, contextList, contextCheckboxes, contextDisplayOrder, contextNamespace

    ; Scan for contexts before showing GUI
    if (!ScanContextsInNamespace()) {
        MsgBox "No contexts found in namespace '" . contextNamespace . "'`n`nPlease check your namespace configuration or create some context pages in Logseq.", "Warning - " VarScriptName
        ; Continue anyway to allow task creation without context
    }

    ; Organize contexts into groups
    contextGroups := OrganizeContexts(contextList)

    ; Debug: Show what was found (can be removed later)
    ; MsgBox "Top-level: " . contextGroups.topLevel.Length . "`nNested: " . contextGroups.nested.Length

    ; Calculate GUI dimensions - always 2 columns now
    columnWidth := 280
    guiWidth := 600

    ; Calculate max rows needed (use the larger of the two columns)
    maxRows := Max(contextGroups.topLevel.Length, contextGroups.nested.Length)
    contextGroupHeight := 80 + (maxRows * 25)

    ; Create the GUI
    taskGui := Gui("+AlwaysOnTop", VarScriptName " " VarVersionNo)

    ; Add status checkboxes
    taskGui.Add("Text", "x10 y10 w" . guiWidth, "Task Status:")
    taskGui.Add("GroupBox", "x10 y30 w" . guiWidth . " h60", "Status")
    taskGui.Add("Checkbox", "x20 y55 vTodoCheck Checked", "TODO")
    taskGui.Add("Checkbox", "x110 y55 vWaitingCheck", "WAITING")
    taskGui.Add("Checkbox", "x220 y55 vDoingCheck", "DOING")

    ; Add task input field
    currentY := 100
    taskGui.Add("Text", "x10 y" . currentY . " w" . guiWidth, "Task Description:")
    currentY += 20
    taskInput := taskGui.Add("Edit", "x10 y" . currentY . " w" . guiWidth . " r4 vTaskInput", clipText)
    taskInputHwnd := taskInput.Hwnd

    ; Add context section
    currentY += 90
    taskGui.Add("Text", "x10 y" . currentY . " w" . guiWidth, "Context (Namespace: " . contextNamespace . "):")
    currentY += 20

    groupBoxY := currentY
    taskGui.Add("GroupBox", "x10 y" . groupBoxY . " w" . guiWidth . " h" . contextGroupHeight, "Context")

    ; Clear the checkbox arrays
    contextCheckboxes := []
    contextDisplayOrder := []  ; Track which context each checkbox represents
    global contextShortcutMap := Map()  ; Map letter shortcuts to context indices
    usedLetters := Map()  ; Track which letters are already used
    usedLetters["t"] := true  ; Reserved for TODO
    usedLetters["w"] := true  ; Reserved for WAITING
    usedLetters["d"] := true  ; Reserved for DOING
    globalContextIndex := 1

    ; Starting positions
    leftColumnX := 20
    rightColumnX := 320
    columnStartY := groupBoxY + 25

    ; === LEFT COLUMN: Top-level contexts ===
    if (contextGroups.topLevel.Length > 0) {
        taskGui.Add("Text", "x" . leftColumnX . " y" . columnStartY . " w250", "─── Top-level ───")

        Loop contextGroups.topLevel.Length {
            contextName := contextGroups.topLevel[A_Index]
            contextDisplayOrder.Push(contextName)  ; Store in display order
            checkboxY := columnStartY + 25 + ((A_Index - 1) * 25)

            shortcutHint := ""
            if (globalContextIndex <= 10) {
                ; First 10 get number shortcuts
                shortcutKey := Mod(globalContextIndex, 10)
                shortcutHint := " (" . shortcutKey . ")"
            } else {
                ; Others get letter shortcuts
                letterShortcut := FindAvailableLetter(contextName, usedLetters)
                if (letterShortcut != "") {
                    usedLetters[letterShortcut] := true
                    contextShortcutMap[letterShortcut] := globalContextIndex
                    shortcutHint := " (" . StrUpper(letterShortcut) . ")"
                }
            }

            checkboxVarName := "ContextCheck" . globalContextIndex
            cb := taskGui.Add("Checkbox", "x" . leftColumnX . " y" . checkboxY . " w250 v" . checkboxVarName, contextName . shortcutHint)
            contextCheckboxes.Push(cb)
            globalContextIndex++
        }
    }

    ; === RIGHT COLUMN: Nested contexts ===
    if (contextGroups.nested.Length > 0) {
        taskGui.Add("Text", "x" . rightColumnX . " y" . columnStartY . " w250", "─── Nested ───")

        Loop contextGroups.nested.Length {
            contextName := contextGroups.nested[A_Index]
            contextDisplayOrder.Push(contextName)  ; Store in display order
            checkboxY := columnStartY + 25 + ((A_Index - 1) * 25)

            ; For nested contexts, show the full path
            ; e.g., "Consume/Read" or "PC/Discord"
            displayName := contextName

            ; Nested contexts get letter shortcuts
            letterShortcut := FindAvailableLetter(contextName, usedLetters)
            shortcutHint := ""
            if (letterShortcut != "") {
                usedLetters[letterShortcut] := true
                contextShortcutMap[letterShortcut] := globalContextIndex
                shortcutHint := " (" . StrUpper(letterShortcut) . ")"
            }

            checkboxVarName := "ContextCheck" . globalContextIndex
            cb := taskGui.Add("Checkbox", "x" . rightColumnX . " y" . checkboxY . " w250 v" . checkboxVarName, displayName . shortcutHint)
            contextCheckboxes.Push(cb)
            globalContextIndex++
        }
    }

    ; If no contexts at all
    if (contextList.Length = 0) {
        taskGui.Add("Text", "x20 y" . (columnStartY + 25), "No contexts found. Check namespace configuration.")
    }

    ; Add buttons
    buttonY := groupBoxY + contextGroupHeight + 10
    taskGui.Add("Button", "x10 y" . buttonY . " w120 Default vSubmitBtn", "Submit").OnEvent("Click", SubmitButtonHandler)
    taskGui.Add("Button", "x140 y" . buttonY . " w150 vSubmitOpenBtn", "Submit and Open").OnEvent("Click", SubmitAndOpenButtonHandler)
    taskGui.Add("Button", "x300 y" . buttonY . " w100 vCancelBtn", "Cancel").OnEvent("Click", CancelButtonHandler)

    ; Add keyboard shortcuts info
    buttonY += 35
    taskGui.Add("Text", "x10 y" . buttonY . " w" . guiWidth, "Shortcuts (when NOT typing in text field):")
    buttonY += 20
    taskGui.Add("Text", "x10 y" . buttonY . " w" . guiWidth, "Status: T=TODO, W=WAITING, D=DOING | Context: 0-9, or letter shown")

    ; Set up events
    taskGui.OnEvent("Close", CancelButtonHandler)
    taskGui.OnEvent("Escape", CancelButtonHandler)
    OnMessage(0x0102, HandleChar)

    ; Focus and show
    taskInput.Focus()
    taskGui.Show()
}

; Handle WM_CHAR message to intercept key presses
HandleChar(wParam, lParam, msg, hwnd) {
    global taskGui, taskInputHwnd, contextDisplayOrder, contextShortcutMap

    ; Skip processing if the GUI doesn't exist
    if (!taskGui || !IsObject(taskGui))
        return

    ; Only process keypresses when focus is NOT on our text input
    ; The hwnd parameter tells us which control received this WM_CHAR message
    if (hwnd == taskInputHwnd)
        return  ; Let normal typing work in the text field

    ; Get the character typed
    char := Chr(wParam)
    charLower := StrLower(char)

    ; Process the character - Status shortcuts first
    Switch charLower {
        case "t":
            taskGui["TodoCheck"].Value := 1
            taskGui["WaitingCheck"].Value := 0
            taskGui["DoingCheck"].Value := 0
            return 0

        case "w":
            taskGui["TodoCheck"].Value := 0
            taskGui["WaitingCheck"].Value := 1
            taskGui["DoingCheck"].Value := 0
            return 0

        case "d":
            taskGui["TodoCheck"].Value := 0
            taskGui["WaitingCheck"].Value := 0
            taskGui["DoingCheck"].Value := 1
            return 0

        case "0", "1", "2", "3", "4", "5", "6", "7", "8", "9":
            ; Clear all context checkboxes first
            Loop contextDisplayOrder.Length {
                checkboxName := "ContextCheck" . A_Index
                Try {
                    taskGui[checkboxName].Value := 0
                }
            }

            ; Determine which context to select
            contextIndex := (char = "0") ? 10 : Integer(char)

            ; Set the selected context if it exists
            if (contextIndex <= contextDisplayOrder.Length) {
                checkboxName := "ContextCheck" . contextIndex
                Try {
                    taskGui[checkboxName].Value := 1
                }
            }
            return 0

        default:
            ; Check if this letter is a context shortcut
            if (contextShortcutMap.Has(charLower)) {
                ; Clear all context checkboxes first
                Loop contextDisplayOrder.Length {
                    checkboxName := "ContextCheck" . A_Index
                    Try {
                        taskGui[checkboxName].Value := 0
                    }
                }

                ; Set the selected context
                contextIndex := contextShortcutMap[charLower]
                checkboxName := "ContextCheck" . contextIndex
                Try {
                    taskGui[checkboxName].Value := 1
                }
                return 0
            }
    }
}

; Function for Alt+Enter in Logseq
LogseqAddTodo() {
    SendInput "^{Enter}"
    SendInput "{End}"
    SendInput "+{Enter}"
    SendInput "context:: [[-/"
    return
}

; Tray menu handler for Reset Logseq Path
ResetLogseqPath(*) {
    global customDir, iniPath, VarScriptName, VarVersionNo

    result := MsgBox("Current path: " . customDir . "`n`nDo you want to select a new Logseq journal folder?", VarScriptName " - Reset Path", "YesNo Icon?")

    if (result = "Yes") {
        if newDir := DirSelect(, 3, "Select your Logseq journal folder") {
            customDir := newDir
            IniWrite(customDir, iniPath, "General", "CustomPath")
            TrayTip "Path updated to:`n" . customDir, VarScriptName " " VarVersionNo, 1
        }
    }
}

; Tray menu handler for Reset Context Namespace
ResetContextNamespace(*) {
    global contextNamespace, iniPath, VarScriptName, VarVersionNo

    currentNS := (contextNamespace != "") ? contextNamespace : "(not set)"

    result := MsgBox("Current namespace: " . currentNS . "`n`nDo you want to set a new context namespace?", VarScriptName " - Reset Namespace", "YesNo Icon?")

    if (result = "Yes") {
        ib := InputBox("Enter the namespace for your contexts (e.g., 'c' for c/PC, c/Office):", VarScriptName " - Set Namespace", "w300 h150", contextNamespace)

        if (ib.Result = "OK" && ib.Value != "") {
            contextNamespace := Trim(ib.Value)
            IniWrite(contextNamespace, iniPath, "General", "ContextNamespace")

            if (ScanContextsInNamespace()) {
                TrayTip "Namespace updated to: " . contextNamespace . "`nFound " . contextList.Length . " context(s)", VarScriptName " " VarVersionNo, 1
            } else {
                TrayTip "Namespace updated to: " . contextNamespace . "`nNo contexts found yet", VarScriptName " " VarVersionNo, 1
            }
        }
    }
}

; Tray menu handler for About
ShowAbout(*) {
    global customDir, contextNamespace, contextList, VarScriptName, VarVersionNo

    aboutText := VarScriptName . " " . VarVersionNo . "`n`n"
    aboutText .= "HOW TO USE:`n"
    aboutText .= "1. Select any text and press SHIFT+CTRL+L to capture it`n"
    aboutText .= "2. Choose task status (TODO/WAITING/DOING)`n"
    aboutText .= "3. Optionally select a context`n"
    aboutText .= "4. Click Submit to add to journal`n`n"
    aboutText .= "KEYBOARD SHORTCUTS (when not typing):`n"
    aboutText .= "T = TODO, W = WAITING, D = DOING`n"
    aboutText .= "0-9 = First 10 top-level contexts`n"
    aboutText .= "Letters = Additional contexts (shown in parentheses)`n`n"
    aboutText .= "MULTILINE SUPPORT:`n"
    aboutText .= "First line becomes the task, remaining lines become sub-blocks`n`n"
    aboutText .= "CURRENT SETTINGS:`n"
    aboutText .= "Journal Path: " . customDir . "`n"
    aboutText .= "Context Namespace: " . contextNamespace . "`n"
    aboutText .= "Contexts Found: " . contextList.Length . "`n"

    MsgBox aboutText, "About " . VarScriptName, 64
}

;------------------------------------------------------------------------------
; Script Initialization
;------------------------------------------------------------------------------

A_IconTip := VarScriptName " " VarVersionNo " " Varblurb

Try TraySetIcon(A_ScriptDir "\" VarScriptName ".ico")
Catch
    TrayTip "Remember to add " VarScriptName ".ico to same folder as " VarScriptName ".ahk", VarScriptName

;------------------------------------------------------------------------------
; Setup Tray Menu
;------------------------------------------------------------------------------
A_TrayMenu.Insert("1&", "About " . VarScriptName, ShowAbout)
A_TrayMenu.Insert("2&", "Reset Logseq Path", ResetLogseqPath)
A_TrayMenu.Insert("3&", "Reset Context Namespace", ResetContextNamespace)
A_TrayMenu.Insert("4&")  ; Separator

;------------------------------------------------------------------------------
; Check if INI file exists with path to folder
;------------------------------------------------------------------------------
if !IniRead(iniPath, "General", "CustomPath", 0)
{
    MsgBox "Choose the folder where your journal files are.", VarScriptName " " VarVersionNo
    if !customDir := DirSelect()
        MsgBox "You have to select journalfolder for script to work.", "Error -" VarScriptName " " VarVersionNo

    IniWrite(customDir, iniPath, "General", "CustomPath")
}
customDir := IniRead(iniPath, "General", "CustomPath")

; Check if namespace is configured
if !IniRead(iniPath, "General", "ContextNamespace", 0)
{
    MsgBox "Now, please specify the namespace for your contexts.`n`nFor example, if your contexts are 'c/PC', 'c/Office', etc., enter 'c'", VarScriptName " " VarVersionNo

    ib := InputBox("Enter the namespace for your contexts:", VarScriptName " - Set Namespace", "w300 h150", "c")

    if (ib.Result = "OK" && ib.Value != "") {
        contextNamespace := Trim(ib.Value)
        IniWrite(contextNamespace, iniPath, "General", "ContextNamespace")
    } else {
        MsgBox "You need to set a context namespace for the script to work properly.", "Warning - " VarScriptName " " VarVersionNo
        contextNamespace := "c"
        IniWrite(contextNamespace, iniPath, "General", "ContextNamespace")
    }
}
contextNamespace := IniRead(iniPath, "General", "ContextNamespace")

; Scan for contexts on startup
ScanContextsInNamespace()

; Show welcome message
If IniRead(iniPath, "General", "CustomPath", 0)
    TrayTip "Capturing to: " customDir "`nNamespace: " contextNamespace "`nContexts found: " contextList.Length "`n`nCapture to Logseq by pressing CTRL+Shift+L", VarScriptName " " VarVersionNo

;------------------------------------------------------------------------------
; Hotkeys
;------------------------------------------------------------------------------
+^l:: {
    oldClip := ClipboardAll()
    A_Clipboard := ""
    Send "^c"

    if ClipWait(1) {
        clipText := A_Clipboard
        ShowLogseqAddGUI(clipText)
    } else {
        ShowLogseqAddGUI("")
    }

    A_Clipboard := oldClip
}

#HotIf WinActive("ahk_exe Logseq.exe")
!Enter::LogseqAddTodo()
#HotIf
