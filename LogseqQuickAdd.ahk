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
;                       Added Logseq API support with FileAppend fallback
;                       API always preferred; file fallback with warning
;                       Added None status, letter cycling, parent→child nav
;
;------------------------------------------------------------------------------
;SETTINGS
;------------------------------------------------------------------------------
#Requires AutoHotkey v2.0+
#SingleInstance force

;------------------------------------------------------------------------------
; Global Variables - Must be declared first
;------------------------------------------------------------------------------
global VarScriptName := "LogseqQuickAdd"
global VarVersionNo := "v021"
global Varblurb := "`nPress SHIFT+CTRL+L to add`nyour clipboard as task to Logseq"
global customDir := ""
global contextNamespace := ""
global contextList := []  ; Array to store found contexts
global taskGui := ""
global taskInputHwnd := 0  ; Store the hwnd of the task input control
global contextCheckboxes := []  ; Array to store checkbox controls
global contextDisplayOrder := []  ; Array to store contexts in the order they appear in GUI
global iniPath := A_ScriptDir "\" VarScriptName ".ini"
global logseqApiToken := ""
global cycleKey := ""          ; Track which letter key is being cycled
global cycleIndex := 0         ; Current position in the cycle
global cycleTimer := 0         ; Timer handle for cycle reset
global selectedTopLevel := ""  ; Currently selected top-level context (for parent→child nav)
global targetMode := "Logseq"          ; "Logseq" or "NeovimLog"
global nvimServerAddress := ""         ; Neovim RPC pipe address (e.g. \\.\pipe\nvim)
global targetSubMenu := ""            ; Tray submenu for target selection

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
    allLetters := "abcdefghijklmnopqrstuvwxyz"  ; All letters available (status uses numbers)
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

; Function to get current journal page name
GetTodayJournalPage() {
    ; Logseq journal page format: YYYYMMDD (e.g., 20260213)
    return A_YYYY . A_MM . A_DD
}

; Function to call Logseq API to append block
CallLogseqApi(content, pageName) {
    global logseqApiToken

    ; Prepare the API request
    url := "http://127.0.0.1:12315/api"

    ; Escape quotes in content for JSON
    escapedContent := StrReplace(content, '"', '\"')
    escapedContent := StrReplace(escapedContent, "`n", "\n")
    escapedContent := StrReplace(escapedContent, "`r", "")

    ; Build JSON payload for append_block_in_page method
    jsonPayload := '{"method":"logseq.Editor.appendBlockInPage","args":["' . pageName . '","' . escapedContent . '"]}'

    ; Create HTTP request
    try {
        whr := ComObject("WinHttp.WinHttpRequest.5.1")
        whr.Open("POST", url, false)
        whr.SetRequestHeader("Content-Type", "application/json")
        whr.SetRequestHeader("Authorization", "Bearer " . logseqApiToken)
        whr.Send(jsonPayload)

        ; Check response
        if (whr.Status = 200) {
            return {success: true, message: "Task added via API"}
        } else {
            return {success: false, message: "API returned status " . whr.Status . ": " . whr.ResponseText}
        }
    } catch as err {
        return {success: false, message: "API call failed: " . err.Message}
    }
}

; Function to call Neovim RPC to append task via external.lua
CallNeovimRpc(taskText, statusKeyword, contextPath) {
    global nvimServerAddress

    ; Escape special characters for JSON string
    escapedText := StrReplace(taskText, "\", "\\")
    escapedText := StrReplace(escapedText, '"', '\"')
    escapedText := StrReplace(escapedText, "`n", "\n")
    escapedText := StrReplace(escapedText, "`r", "")

    escapedContext := StrReplace(contextPath, "\", "\\")
    escapedContext := StrReplace(escapedContext, '"', '\"')

    ; Build JSON payload for the Lua function
    jsonPayload := '{\"text\":\"' . escapedText . '\",\"status\":\"' . statusKeyword . '\",\"context\":\"' . escapedContext . '\"}'

    ; Build the nvim command - luaeval calls require('logseq.external').add_task(json)
    luaExpr := "luaeval(""require('logseq.external').add_task('" . jsonPayload . "')"")"
    nvimCmd := 'nvim --server "' . nvimServerAddress . '" --remote-expr "' . luaExpr . '"'

    try {
        shell := ComObject("WScript.Shell")
        exec := shell.Exec('cmd /c ' . nvimCmd)
        output := Trim(exec.StdOut.ReadAll())
        errOutput := Trim(exec.StdErr.ReadAll())

        if (output = "ok") {
            return {success: true, message: "Task added via Neovim RPC"}
        } else if (output != "") {
            return {success: false, message: "Neovim returned: " . output}
        } else if (errOutput != "") {
            return {success: false, message: "Neovim error: " . errOutput}
        } else {
            return {success: false, message: "No response from Neovim. Is it running with --listen " . nvimServerAddress . "?"}
        }
    } catch as err {
        return {success: false, message: "Neovim RPC failed: " . err.Message . "`n`nMake sure Neovim is running with:`nnvim --listen " . nvimServerAddress}
    }
}

; Function to save task using file method (fallback)
SaveTaskToFile(processedTask) {
    global customDir, VarScriptName

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
    finalText := ""
    if (shouldAddNewline) {
        finalText := "`n" . processedTask . "`n- " . "`n"
    } else {
        finalText := processedTask . "`n- " . "`n"
    }

    ; Append to file
    Try {
        FileAppend(finalText, CaptureFilePath)
        return {success: true, message: "Task added to file: " . CaptureFilePath}
    } Catch as err {
        return {success: false, message: "Error writing to file: " . CaptureFilePath . "`n`nError: " . err.Message}
    }
}

; Function to save task to Logseq journal
SaveTask(openLogseq := false) {
    global taskGui, customDir, contextNamespace, contextDisplayOrder, iniPath, VarScriptName, VarVersionNo
    global logseqApiToken

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
    statusPrefix := "- "  ; Start with dash and space for Logseq blocks
    if (savedValues.TodoCheck)
        statusPrefix .= "TODO "
    else if (savedValues.WaitingCheck)
        statusPrefix .= "WAITING "
    else if (savedValues.DoingCheck)
        statusPrefix .= "DOING "
    ; NoneCheck = just "- " with no status keyword

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

    ; --- Save method: branch on target mode ---
    result := {success: false, message: ""}
    methodUsed := ""

    if (targetMode = "NeovimLog") {
        ; Determine status keyword for Neovim RPC (without "- " prefix)
        statusKeyword := ""
        if (savedValues.TodoCheck)
            statusKeyword := "TODO"
        else if (savedValues.WaitingCheck)
            statusKeyword := "WAITING"
        else if (savedValues.DoingCheck)
            statusKeyword := "DOING"

        ; Build full context path for Neovim
        contextPath := ""
        if (contextName != "")
            contextPath := contextNamespace . "/" . contextName

        result := CallNeovimRpc(taskText, statusKeyword, contextPath)
        if (result.success) {
            methodUsed := "Neovim RPC"
        }
    } else {
        ; --- Logseq target: existing API / file fallback logic ---
        processedTask := ProcessMultilineText(taskText, statusPrefix, contextSuffix)

        if (logseqApiToken != "") {
            ; API token is set — always try API first
            pageName := GetTodayJournalPage()
            result := CallLogseqApi(processedTask, pageName)

            if (result.success) {
                methodUsed := "API"
            } else {
                ; API failed — warn user and fall back to file method
                apiWarning := "⚠ API unavailable: " . result.message . "`nFalling back to file method..."
                TrayTip apiWarning, VarScriptName " " VarVersionNo, 2  ; Icon 2 = Warning
                Sleep 1500  ; Give user time to see the warning
                result := SaveTaskToFile(processedTask)
                if (result.success) {
                    methodUsed := "File (API fallback)"
                }
            }
        } else {
            ; No API token configured — warn and use file method
            TrayTip "⚠ No API token set — using file method.`nSet token via tray menu for API support.", VarScriptName " " VarVersionNo, 2
            Sleep 1000
            result := SaveTaskToFile(processedTask)
            if (result.success) {
                methodUsed := "File (no API token)"
            }
        }
    }

    ; Show result to user
    if (result.success) {
        confirmMsg := "Task added (" . methodUsed . ")"
        if (contextName != "") {
            confirmMsg .= "`nContext: " . contextName
        }
        TrayTip confirmMsg, VarScriptName " " VarVersionNo, 1
    } else {
        MsgBox result.message, "Error - " VarScriptName
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

    ; Calculate GUI dimensions - always 2 columns now
    columnWidth := 280
    guiWidth := 600

    ; Calculate max rows needed (use the larger of the two columns)
    maxRows := Max(contextGroups.topLevel.Length, contextGroups.nested.Length)
    contextGroupHeight := 80 + (maxRows * 25)

    ; Create the GUI
    taskGui := Gui("+AlwaysOnTop", VarScriptName " " VarVersionNo " [" . targetMode . "]")

    ; Add status checkboxes
    taskGui.Add("Text", "x10 y10 w" . guiWidth, "Task Status:")
    taskGui.Add("GroupBox", "x10 y30 w" . guiWidth . " h60", "Status (|/0=None, 1=TODO, 2=WAITING, 3=DOING)")
    taskGui.Add("Checkbox", "x20 y55 vNoneCheck", "(|/0) None")
    taskGui.Add("Checkbox", "x140 y55 vTodoCheck Checked", "(1) TODO")
    taskGui.Add("Checkbox", "x260 y55 vWaitingCheck", "(2) WAITING")
    taskGui.Add("Checkbox", "x400 y55 vDoingCheck", "(3) DOING")

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
    ; No letters reserved — status uses numbers now, all letters available for contexts
    globalContextIndex := 1

    ; Starting positions
    leftColumnX := 20
    rightColumnX := 320
    columnStartY := groupBoxY + 25

    ; === LEFT COLUMN: Top-level contexts ===
    if (contextGroups.topLevel.Length > 0) {
        taskGui.Add("Text", "x" . leftColumnX . " y" . columnStartY . " w250", "─── Top-level (press first letter to cycle) ───")

        Loop contextGroups.topLevel.Length {
            contextName := contextGroups.topLevel[A_Index]
            contextDisplayOrder.Push(contextName)  ; Store in display order
            checkboxY := columnStartY + 25 + ((A_Index - 1) * 25)

            ; Show first letter as hint (cycling handles the rest)
            firstLetter := StrUpper(SubStr(contextName, 1, 1))
            shortcutHint := " (" . firstLetter . ")"

            checkboxVarName := "ContextCheck" . globalContextIndex
            cb := taskGui.Add("Checkbox", "x" . leftColumnX . " y" . checkboxY . " w250 v" . checkboxVarName, contextName . shortcutHint)
            contextCheckboxes.Push(cb)
            globalContextIndex++
        }
    }

    ; === RIGHT COLUMN: Nested contexts ===
    if (contextGroups.nested.Length > 0) {
        taskGui.Add("Text", "x" . rightColumnX . " y" . columnStartY . " w250", "─── Nested (select parent, then letter) ───")

        Loop contextGroups.nested.Length {
            contextName := contextGroups.nested[A_Index]
            contextDisplayOrder.Push(contextName)  ; Store in display order
            checkboxY := columnStartY + 25 + ((A_Index - 1) * 25)

            ; Show first letter of the child part as hint
            parts := StrSplit(contextName, "/")
            childPart := parts[parts.Length]
            firstLetter := StrUpper(SubStr(childPart, 1, 1))
            shortcutHint := " (" . firstLetter . ")"

            checkboxVarName := "ContextCheck" . globalContextIndex
            cb := taskGui.Add("Checkbox", "x" . rightColumnX . " y" . checkboxY . " w250 v" . checkboxVarName, contextName . shortcutHint)
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
    taskGui.Add("Text", "x10 y" . buttonY . " w" . guiWidth, "Status: |/0=None, 1=TODO, 2=WAITING, 3=DOING")
    buttonY += 15
    taskGui.Add("Text", "x10 y" . buttonY . " w" . guiWidth, "Context: Letter=cycle top-level, then letter=pick sub-context")

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
    global contextList, cycleKey, cycleIndex, cycleTimer, selectedTopLevel

    ; Skip processing if the GUI doesn't exist
    if (!taskGui || !IsObject(taskGui))
        return

    ; Only process keypresses when focus is NOT on our text input
    if (hwnd == taskInputHwnd)
        return  ; Let normal typing work in the text field

    ; Get the character typed
    char := Chr(wParam)
    charLower := StrLower(char)

    ; --- Helper closure: clear all context checkboxes ---
    ClearAllContexts() {
        Loop contextDisplayOrder.Length {
            checkboxName := "ContextCheck" . A_Index
            Try {
                taskGui[checkboxName].Value := 0
            }
        }
    }

    ; --- Helper closure: select context by index (1-based into contextDisplayOrder) ---
    SelectContextByIndex(idx) {
        ClearAllContexts()
        if (idx >= 1 && idx <= contextDisplayOrder.Length) {
            checkboxName := "ContextCheck" . idx
            Try {
                taskGui[checkboxName].Value := 1
            }
            ; Track if this is a top-level context for parent→child navigation
            ctxName := contextDisplayOrder[idx]
            if (!InStr(ctxName, "/")) {
                selectedTopLevel := ctxName
            } else {
                selectedTopLevel := ""
            }
        }
    }

    ; --- Helper closure: find the display index for a context name ---
    FindContextIndex(name) {
        Loop contextDisplayOrder.Length {
            if (contextDisplayOrder[A_Index] = name)
                return A_Index
        }
        return 0
    }

    ; === PIPE | or 0 = None status ===
    if (charLower = "|" || charLower = "0") {
        taskGui["NoneCheck"].Value := 1
        taskGui["TodoCheck"].Value := 0
        taskGui["WaitingCheck"].Value := 0
        taskGui["DoingCheck"].Value := 0
        return 0
    }

    ; === NUMBER STATUS SHORTCUTS: 1=TODO, 2=WAITING, 3=DOING ===
    if (charLower = "1") {
        taskGui["NoneCheck"].Value := 0
        taskGui["TodoCheck"].Value := 1
        taskGui["WaitingCheck"].Value := 0
        taskGui["DoingCheck"].Value := 0
        return 0
    }
    if (charLower = "2") {
        taskGui["NoneCheck"].Value := 0
        taskGui["TodoCheck"].Value := 0
        taskGui["WaitingCheck"].Value := 1
        taskGui["DoingCheck"].Value := 0
        return 0
    }
    if (charLower = "3") {
        taskGui["NoneCheck"].Value := 0
        taskGui["TodoCheck"].Value := 0
        taskGui["WaitingCheck"].Value := 0
        taskGui["DoingCheck"].Value := 1
        return 0
    }

    ; === CONTEXT SELECTION (letter-based with cycling and parent→child) ===
    if (charLower ~= "^[a-zæøå]$") {

        ; --- STEP 1: If a top-level context is selected, try parent→child first ---
        if (selectedTopLevel != "") {
            subOptions := []
            Loop contextDisplayOrder.Length {
                ctxName := contextDisplayOrder[A_Index]
                ; Match nested contexts under the selected top-level that start with pressed letter
                if (InStr(ctxName, "/")) {
                    parts := StrSplit(ctxName, "/")
                    parentPart := parts[1]
                    childPart := parts[parts.Length]
                    if (parentPart = selectedTopLevel && StrLower(SubStr(childPart, 1, 1)) = charLower) {
                        subOptions.Push({name: ctxName, index: A_Index})
                    }
                }
            }

            if (subOptions.Length > 0) {
                ; Found sub-contexts — select the first match (or cycle if multiple)
                if (charLower = cycleKey && subOptions.Length > 1) {
                    cycleIndex := Mod(cycleIndex, subOptions.Length) + 1
                } else {
                    cycleKey := charLower
                    cycleIndex := 1
                }
                SelectContextByIndex(subOptions[cycleIndex].index)
                ; Keep selectedTopLevel so user can pick another sub-context
                selectedTopLevel := selectedTopLevel
                ; Reset cycle timer
                if (cycleTimer)
                    SetTimer(cycleTimer, 0)
                cycleTimer := SetTimer(ResetCycleState, -1000)
                return 0
            }
            ; No sub-contexts matched — fall through to top-level cycling
        }

        ; --- STEP 2: Cycle through top-level contexts starting with this letter ---
        topOptions := []
        Loop contextDisplayOrder.Length {
            ctxName := contextDisplayOrder[A_Index]
            if (!InStr(ctxName, "/") && StrLower(SubStr(ctxName, 1, 1)) = charLower) {
                topOptions.Push({name: ctxName, index: A_Index})
            }
        }

        if (topOptions.Length > 0) {
            if (charLower = cycleKey) {
                ; Same letter pressed again — cycle to next
                cycleIndex := Mod(cycleIndex, topOptions.Length) + 1
            } else {
                ; New letter — start fresh
                cycleKey := charLower
                cycleIndex := 1
            }
            SelectContextByIndex(topOptions[cycleIndex].index)
            ; Reset cycle timer (1 second)
            if (cycleTimer)
                SetTimer(cycleTimer, 0)
            cycleTimer := SetTimer(ResetCycleState, -1000)
            return 0
        }

        ; --- STEP 3: Fallback — check legacy letter shortcut map ---
        if (contextShortcutMap.Has(charLower)) {
            ClearAllContexts()
            contextIndex := contextShortcutMap[charLower]
            checkboxName := "ContextCheck" . contextIndex
            Try {
                taskGui[checkboxName].Value := 1
            }
            ; Track if top-level
            ctxName := contextDisplayOrder[contextIndex]
            selectedTopLevel := (!InStr(ctxName, "/")) ? ctxName : ""
            return 0
        }
    }
}

; Timer callback to reset cycling state
ResetCycleState() {
    global cycleKey, cycleIndex, cycleTimer
    cycleKey := ""
    cycleIndex := 0
    cycleTimer := 0
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

; Tray menu handler for API Token
SetApiToken(*) {
    global logseqApiToken, iniPath, VarScriptName, VarVersionNo

    currentToken := (logseqApiToken != "") ? "****" . SubStr(logseqApiToken, -4) : "(not set)"

    instructionText := "To get your API token:`n"
    instructionText .= "1. Open Logseq`n"
    instructionText .= "2. Go to Settings > Features`n"
    instructionText .= "3. Enable 'HTTP APIs server'`n"
    instructionText .= "4. Click 'Auth token' to copy it`n`n"
    instructionText .= "Current token: " . currentToken . "`n`n"
    instructionText .= "Enter your Logseq API token below:"

    ib := InputBox(instructionText, VarScriptName " - API Token", "w400 h300", "")

    if (ib.Result = "OK" && ib.Value != "") {
        logseqApiToken := Trim(ib.Value)
        IniWrite(logseqApiToken, iniPath, "General", "ApiToken")
        TrayTip "API token updated", VarScriptName " " VarVersionNo, 1
    }
}

; Tray menu handlers for Target switching
SwitchToLogseq(*) {
    global targetMode, iniPath, VarScriptName, VarVersionNo, targetSubMenu
    targetMode := "Logseq"
    IniWrite(targetMode, iniPath, "General", "Target")
    targetSubMenu.Check("Logseq")
    targetSubMenu.Uncheck("NeovimLog")
    TrayTip "Target set to Logseq", VarScriptName " " VarVersionNo, 1
}

SwitchToNeovimLog(*) {
    global targetMode, iniPath, VarScriptName, VarVersionNo, targetSubMenu
    targetMode := "NeovimLog"
    IniWrite(targetMode, iniPath, "General", "Target")
    targetSubMenu.Uncheck("Logseq")
    targetSubMenu.Check("NeovimLog")
    TrayTip "Target set to NeovimLog", VarScriptName " " VarVersionNo, 1
}

; Tray menu handler for Neovim Server Address
SetNvimServerAddress(*) {
    global nvimServerAddress, iniPath, VarScriptName, VarVersionNo

    currentAddr := (nvimServerAddress != "") ? nvimServerAddress : "(not set)"

    instructionText := "Neovim must be running with --listen to receive tasks.`n`n"
    instructionText .= "Example: nvim --listen \\.\pipe\nvim`n`n"
    instructionText .= "Current address: " . currentAddr . "`n`n"
    instructionText .= "Enter the Neovim server pipe address:"

    ib := InputBox(instructionText, VarScriptName " - Neovim Server", "w400 h250", nvimServerAddress)

    if (ib.Result = "OK" && ib.Value != "") {
        nvimServerAddress := Trim(ib.Value)
        IniWrite(nvimServerAddress, iniPath, "General", "NvimServerAddress")
        TrayTip "Neovim server address updated to:`n" . nvimServerAddress, VarScriptName " " VarVersionNo, 1
    }
}

; Tray menu handler for About
ShowAbout(*) {
    global customDir, contextNamespace, contextList, VarScriptName, VarVersionNo, logseqApiToken

    aboutText := VarScriptName . " " . VarVersionNo . "`n`n"
    aboutText .= "HOW TO USE:`n"
    aboutText .= "1. Select any text and press SHIFT+CTRL+L to capture it`n"
    aboutText .= "2. Choose task status (TODO/WAITING/DOING)`n"
    aboutText .= "3. Optionally select a context`n"
    aboutText .= "4. Click Submit to add to journal`n`n"
    aboutText .= "KEYBOARD SHORTCUTS (when not typing):`n"
    aboutText .= "|/0 = None (no status), 1 = TODO, 2 = WAITING, 3 = DOING`n"
    aboutText .= "Letters = Cycle through top-level contexts starting with that letter`n"
    aboutText .= "  → Then press another letter to pick a sub-context`n`n"
    aboutText .= "MULTILINE SUPPORT:`n"
    aboutText .= "First line becomes the task, remaining lines become sub-blocks`n`n"
    aboutText .= "SAVE METHOD:`n"
    aboutText .= "API is always preferred. If API is unavailable, the script`n"
    aboutText .= "falls back to direct file writing with a warning notification.`n`n"
    aboutText .= "CURRENT SETTINGS:`n"
    aboutText .= "Target: " . targetMode . "`n"
    aboutText .= "Journal Path: " . customDir . "`n"
    aboutText .= "Context Namespace: " . contextNamespace . "`n"
    aboutText .= "Contexts Found: " . contextList.Length . "`n"
    aboutText .= "API Token: " . (logseqApiToken != "" ? "Set" : "Not set") . "`n"
    aboutText .= "Neovim Server: " . (nvimServerAddress != "" ? nvimServerAddress : "(not set)") . "`n"

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
targetSubMenu := Menu()
targetSubMenu.Add("Logseq", SwitchToLogseq)
targetSubMenu.Add("NeovimLog", SwitchToNeovimLog)

A_TrayMenu.Insert("1&", "About " . VarScriptName, ShowAbout)
A_TrayMenu.Insert("2&", "Target", targetSubMenu)
A_TrayMenu.Insert("3&", "Set Neovim Server Address", SetNvimServerAddress)
A_TrayMenu.Insert("4&", "Reset Logseq Path", ResetLogseqPath)
A_TrayMenu.Insert("5&", "Reset Context Namespace", ResetContextNamespace)
A_TrayMenu.Insert("6&", "Set API Token", SetApiToken)
A_TrayMenu.Insert("7&")  ; Separator

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

; Check if API token is configured
if !IniRead(iniPath, "General", "ApiToken", 0)
{
    instructionText := "Logseq API Integration (Recommended)`n`n"
    instructionText .= "This script always prefers the Logseq HTTP API for adding tasks.`n"
    instructionText .= "If API is unavailable, it will fall back to direct file writing`n"
    instructionText .= "and show a warning notification.`n`n"
    instructionText .= "To enable API:`n"
    instructionText .= "1. Open Logseq`n"
    instructionText .= "2. Go to Settings > Features`n"
    instructionText .= "3. Enable 'HTTP APIs server'`n"
    instructionText .= "4. Click 'Auth token' to copy it`n`n"
    instructionText .= "Do you want to set up the API token now?"

    result := MsgBox(instructionText, VarScriptName " - API Setup", "YesNo Icon?")

    if (result = "Yes") {
        ib := InputBox("Paste your Logseq API token:", VarScriptName " - API Token", "w400 h150", "")

        if (ib.Result = "OK" && ib.Value != "") {
            logseqApiToken := Trim(ib.Value)
            IniWrite(logseqApiToken, iniPath, "General", "ApiToken")
        } else {
            IniWrite("", iniPath, "General", "ApiToken")
        }
    } else {
        IniWrite("", iniPath, "General", "ApiToken")
    }
} else {
    logseqApiToken := IniRead(iniPath, "General", "ApiToken")
}

; Read target mode and Neovim server address
targetMode := IniRead(iniPath, "General", "Target", "Logseq")
nvimServerAddress := IniRead(iniPath, "General", "NvimServerAddress", "\\.\pipe\nvim")

; Set checkmark on the active target in the tray submenu
if (targetMode = "NeovimLog") {
    targetSubMenu.Check("NeovimLog")
} else {
    targetSubMenu.Check("Logseq")
}

; Scan for contexts on startup
ScanContextsInNamespace()

; Show welcome message
If IniRead(iniPath, "General", "CustomPath", 0) {
    welcomeMsg := "Target: " . targetMode . "`nCapturing to: " . customDir . "`nNamespace: " . contextNamespace . "`nContexts found: " . contextList.Length
    if (targetMode = "NeovimLog") {
        welcomeMsg .= "`nNeovim server: " . nvimServerAddress
    } else if (logseqApiToken != "") {
        welcomeMsg .= "`nMethod: API (file fallback if unavailable)"
    } else {
        welcomeMsg .= "`n⚠ No API token — using file method only"
    }
    welcomeMsg .= "`n`nCapture by pressing CTRL+Shift+L"

    TrayTip welcomeMsg, VarScriptName " " VarVersionNo
}

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
