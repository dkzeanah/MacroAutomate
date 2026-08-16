#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

CoordMode("Mouse", "Screen")
CoordMode("Menu", "Screen")

; =====================================================================
; Condensed Desktop Organizer
; AutoHotkey v2
;
; What it does:
;   1. Moves desktop video files into "Desktop - Videos".
;   2. Moves desktop shortcuts and executable files into
;      "Desktop - Programs and Shortcuts".
;   3. Moves ZIP/7Z/RAR and other archive files into "Desktop - Archives".
;   4. Provides a searchable condensed-desktop browser.
;   5. Provides a cursor-position popup browser that behaves like an
;      expanded context menu and supports right-click actions.
;   6. Provides a native tray submenu containing desktop folders.
;
; Files are never overwritten. Name conflicts receive " (2)", " (3)", etc.
;
; Hotkeys:
;   Ctrl+Alt+D   Show/hide the main condensed desktop.
;   Ctrl+Alt+P   Show the all-items popup at the mouse cursor.
;   Ctrl+Alt+F   Show the folders-only popup at the mouse cursor.
;   Ctrl+Alt+O   Organize newly added desktop files.
;   Ctrl+Alt+Z   Undo the latest organization performed this session.
; =====================================================================

global APP_TITLE := "Condensed Desktop Organizer"

global CONFIG := {
    DesktopRoot: A_Desktop,

    ; The public desktop is excluded because changing it affects all users
    ; and may require administrator rights.
    IncludePublicDesktop: false,

    AutoOrganizeOnStart: true,
    ConfirmFirstOrganization: true,

    CategoryFolders: Map(
        "Videos", "Desktop - Videos",
        "Programs", "Desktop - Programs and Shortcuts",
        "Archives", "Desktop - Archives"
    ),

    VideoExtensions: Map(
        "mp4", true,
        "mkv", true,
        "avi", true,
        "mov", true,
        "wmv", true,
        "m4v", true,
        "webm", true,
        "mpeg", true,
        "mpg", true,
        "mts", true,
        "m2ts", true,
        "ts", true,
        "flv", true,
        "vob", true,
        "ogv", true,
        "3gp", true
    ),

    ProgramExtensions: Map(
        "lnk", true,
        "url", true,
        "website", true,
        "exe", true,
        "com", true
    ),

    ArchiveExtensions: Map(
        "zip", true,
        "7z", true,
        "rar", true,
        "tar", true,
        "gz", true,
        "gzip", true,
        "bz2", true,
        "xz", true,
        "tgz", true,
        "cab", true
    ),

    MainWidth: 1180,
    MainHeight: 680,
    PopupWidth: 860,
    PopupHeight: 520,

    MaxIndexedItems: 10000
}


class CondensedDesktopApp {
    __New() {
        global APP_TITLE, CONFIG

        this.AppTitle := APP_TITLE
        this.Config := CONFIG
        this.Items := []
        this.MainRows := Map()
        this.PopupRows := Map()
        this.LastMoveBatch := []
        this.LastSortColumn := 1
        this.LastSortDescending := false
        this.PopupMode := "All items"
        this.SuppressSingleClickUntil := 0

        this.StateDirectory := A_AppData "\CondensedDesktopOrganizer"
        this.LogDirectory := this.StateDirectory "\Logs"
        this.FirstRunMarker := this.StateDirectory "\FirstOrganizationComplete.txt"

        DirCreate(this.StateDirectory)
        DirCreate(this.LogDirectory)

        this.EnsureCategoryFolders()
        this.BuildMainGui()
        this.BuildPopupGui()
        this.BuildTrayMenu()
        this.RefreshEverything()

        if this.Config.AutoOrganizeOnStart
            SetTimer(ObjBindMethod(this, "RunInitialOrganization"), -750)
    }


    ; =================================================================
    ; STARTUP AND PHYSICAL ORGANIZATION
    ; =================================================================

    RunInitialOrganization(*) {
        shouldPrompt := this.Config.ConfirmFirstOrganization
            && !FileExist(this.FirstRunMarker)

        if shouldPrompt {
            answer := MsgBox(
                "This will move matching files located directly on your desktop:`n`n"
                . "• Videos → " this.Config.CategoryFolders["Videos"] "`n"
                . "• Shortcuts and EXE files → "
                . this.Config.CategoryFolders["Programs"] "`n"
                . "• ZIP and archive files → "
                . this.Config.CategoryFolders["Archives"] "`n`n"
                . "Folders and unmatched files will remain where they are.`n"
                . "Existing files will not be overwritten.`n`n"
                . "Continue?",
                this.AppTitle,
                "YesNo Icon?"
            )

            if answer != "Yes"
                return
        }

        this.OrganizeDesktopFiles(false)

        if !FileExist(this.FirstRunMarker) {
            FileAppend(
                "Completed " FormatTime(, "yyyy-MM-dd HH:mm:ss"),
                this.FirstRunMarker,
                "UTF-8"
            )
        }
    }


    EnsureCategoryFolders() {
        for categoryKey, folderName in this.Config.CategoryFolders
            DirCreate(this.Config.DesktopRoot "\" folderName)
    }


    OrganizeDesktopFiles(showResult := true, *) {
        this.EnsureCategoryFolders()

        moveBatch := []
        failures := []
        skipped := 0

        desktopRoots := [this.Config.DesktopRoot]

        if this.Config.IncludePublicDesktop
        && A_DesktopCommon != this.Config.DesktopRoot {
            desktopRoots.Push(A_DesktopCommon)
        }

        for desktopRoot in desktopRoots {
            if !DirExist(desktopRoot)
                continue

            ; Only move files directly on the desktop. Existing project folders
            ; and their contents are never reorganized.
            Loop Files desktopRoot "\*", "F" {
                sourcePath := A_LoopFileFullPath

                if this.PathsEqual(sourcePath, A_ScriptFullPath) {
                    skipped += 1
                    continue
                }

                categoryKey := this.GetPhysicalCategoryForPath(sourcePath)

                if categoryKey = "" {
                    skipped += 1
                    continue
                }

                destinationDirectory :=
                    this.Config.DesktopRoot
                    . "\"
                    . this.Config.CategoryFolders[categoryKey]

                try {
                    destinationPath := this.MoveItemPreservingName(
                        sourcePath,
                        destinationDirectory
                    )

                    if destinationPath != "" {
                        moveBatch.Push({
                            OriginalPath: sourcePath,
                            CurrentPath: destinationPath,
                            Category: categoryKey
                        })
                    }
                } catch Error as err {
                    failures.Push(A_LoopFileName ": " err.Message)
                }
            }
        }

        this.LastMoveBatch := moveBatch

        if moveBatch.Length > 0
            this.WriteMoveLog(moveBatch, failures)

        this.RefreshEverything()

        if showResult {
            message :=
                "Desktop organization finished.`n`n"
                . "Moved: " moveBatch.Length "`n"
                . "Skipped/unmatched: " skipped "`n"
                . "Failed: " failures.Length

            if failures.Length > 0 {
                message .= "`n`nFailures:"

                maxFailuresToShow := Min(failures.Length, 8)

                Loop maxFailuresToShow
                    message .= "`n• " failures[A_Index]

                if failures.Length > maxFailuresToShow
                    message .= "`n• Additional failures are in the log."
            }

            MsgBox(
                message,
                this.AppTitle,
                failures.Length > 0 ? "Icon!" : "Iconi"
            )
        }
    }


    UndoLastOrganization(*) {
        if this.LastMoveBatch.Length = 0 {
            MsgBox(
                "There is no organization batch to undo in this script session.",
                this.AppTitle,
                "Iconi"
            )
            return
        }

        answer := MsgBox(
            "Move the latest organized files back to their original locations?",
            this.AppTitle,
            "YesNo Icon?"
        )

        if answer != "Yes"
            return

        restored := 0
        failures := []

        ; Reverse order prevents unusual same-name move chains from colliding.
        index := this.LastMoveBatch.Length

        while index >= 1 {
            moveRecord := this.LastMoveBatch[index]
            currentPath := moveRecord.CurrentPath
            originalPath := moveRecord.OriginalPath

            if !FileExist(currentPath) && !DirExist(currentPath) {
                failures.Push(
                    "Missing: " currentPath
                )
                index -= 1
                continue
            }

            originalDirectory := this.GetParentDirectory(originalPath)
            DirCreate(originalDirectory)

            restorePath := this.GetUniqueDestinationPath(
                originalDirectory,
                this.GetLeafName(originalPath)
            )

            try {
                if DirExist(currentPath)
                    DirMove(currentPath, restorePath)
                else
                    FileMove(currentPath, restorePath)

                restored += 1
            } catch Error as err {
                failures.Push(
                    this.GetLeafName(currentPath) ": " err.Message
                )
            }

            index -= 1
        }

        this.LastMoveBatch := []
        this.RefreshEverything()

        MsgBox(
            "Undo completed.`n`n"
            . "Restored: " restored "`n"
            . "Failed: " failures.Length,
            this.AppTitle,
            failures.Length > 0 ? "Icon!" : "Iconi"
        )
    }


    GetPhysicalCategoryForPath(path) {
        extension := this.GetExtension(path)

        if extension = ""
            return ""

        if this.Config.VideoExtensions.Has(extension)
            return "Videos"

        if this.Config.ProgramExtensions.Has(extension)
            return "Programs"

        if this.Config.ArchiveExtensions.Has(extension)
            return "Archives"

        return ""
    }


    MoveItemPreservingName(sourcePath, destinationDirectory) {
        if !FileExist(sourcePath) && !DirExist(sourcePath)
            throw Error("Source item no longer exists.")

        DirCreate(destinationDirectory)

        sourceDirectory := this.GetParentDirectory(sourcePath)

        if this.PathsEqual(sourceDirectory, destinationDirectory)
            return ""

        destinationPath := this.GetUniqueDestinationPath(
            destinationDirectory,
            this.GetLeafName(sourcePath)
        )

        if DirExist(sourcePath)
            DirMove(sourcePath, destinationPath)
        else
            FileMove(sourcePath, destinationPath)

        return destinationPath
    }


    WriteMoveLog(moveBatch, failures) {
        logPath :=
            this.LogDirectory
            . "\MoveLog_"
            . FormatTime(, "yyyyMMdd_HHmmss")
            . ".tsv"

        text := "Original Path`tNew Path`tCategory`r`n"

        for moveRecord in moveBatch {
            text .=
                moveRecord.OriginalPath
                . "`t"
                . moveRecord.CurrentPath
                . "`t"
                . moveRecord.Category
                . "`r`n"
        }

        if failures.Length > 0 {
            text .= "`r`nFailures`r`n"

            for failure in failures
                text .= failure "`r`n"
        }

        FileAppend(text, logPath, "UTF-8")
    }


    ; =================================================================
    ; MAIN GUI
    ; =================================================================

    BuildMainGui() {
        this.MainGui := Gui(
            "+Resize +MinSize980x500",
            this.AppTitle
        )

        this.MainGui.SetFont("s10", "Segoe UI")

        this.MainSearch := this.MainGui.AddEdit(
            "x10 y10 w410 h28"
        )

        this.SetCueBanner(
            this.MainSearch,
            "Search name, type, category, or path"
        )

        this.MainFilter := this.MainGui.AddDropDownList(
            "x430 y10 w180 Choose1",
            [
                "All items",
                "Folders only",
                "Files only",
                "Videos",
                "Programs and Shortcuts",
                "Archives",
                "Desktop root"
            ]
        )

        this.MainClickAction := this.MainGui.AddDropDownList(
            "x620 y10 w190 Choose1",
            [
                "Single click: Select only",
                "Single click: Open",
                "Single click: Show in Explorer"
            ]
        )

        this.MainOrganizeButton := this.MainGui.AddButton(
            "x820 y10 w105 h28",
            "Organize"
        )

        this.MainRefreshButton := this.MainGui.AddButton(
            "x935 y10 w90 h28",
            "Refresh"
        )

        this.MainPopupButton := this.MainGui.AddButton(
            "x1035 y10 w130 h28",
            "Popup Browser"
        )

        this.MainList := this.MainGui.AddListView(
            "x10 y48 w1155 h565 Grid FullRowSelect -Multi",
            [
                "Name",
                "Kind",
                "Category",
                "Size",
                "Modified",
                "Path"
            ]
        )

        this.MainStatus := this.MainGui.AddText(
            "x10 y623 w1155 h28 +0x200",
            ""
        )

        this.MainSearch.OnEvent(
            "Change",
            ObjBindMethod(this, "RefreshMainList")
        )

        this.MainFilter.OnEvent(
            "Change",
            ObjBindMethod(this, "RefreshMainList")
        )

        this.MainOrganizeButton.OnEvent(
            "Click",
            ObjBindMethod(this, "OrganizeDesktopFiles").Bind(true)
        )

        this.MainRefreshButton.OnEvent(
            "Click",
            ObjBindMethod(this, "RefreshEverything")
        )

        this.MainPopupButton.OnEvent(
            "Click",
            ObjBindMethod(this, "ShowPopup").Bind("All items")
        )

        this.MainList.OnEvent(
            "Click",
            ObjBindMethod(this, "OnMainSingleClick")
        )

        this.MainList.OnEvent(
            "DoubleClick",
            ObjBindMethod(this, "OnMainDoubleClick")
        )

        this.MainList.OnEvent(
            "ContextMenu",
            ObjBindMethod(this, "OnMainContextMenu")
        )

        this.MainList.OnEvent(
            "ColClick",
            ObjBindMethod(this, "OnColumnClick")
        )

        this.MainGui.OnEvent(
            "Size",
            ObjBindMethod(this, "OnMainResize")
        )

        this.MainGui.OnEvent(
            "Close",
            ObjBindMethod(this, "HideMain")
        )

        this.MainGui.OnEvent(
            "Escape",
            ObjBindMethod(this, "HideMain")
        )

        this.MainGui.OnEvent(
            "DropFiles",
            ObjBindMethod(this, "OnDropFiles")
        )

        this.MainList.ModifyCol(1, 240)
        this.MainList.ModifyCol(2, 120)
        this.MainList.ModifyCol(3, 180)
        this.MainList.ModifyCol(4, 95)
        this.MainList.ModifyCol(5, 145)
        this.MainList.ModifyCol(6, 500)
    }


    OnMainResize(guiObj, minMax, width, height) {
        if minMax = -1
            return

        listWidth := Max(400, width - 20)
        listHeight := Max(250, height - 115)

        this.MainSearch.Move(, , Max(220, width - 770))
        this.MainFilter.Move(Max(240, width - 750))
        this.MainClickAction.Move(Max(430, width - 560))
        this.MainOrganizeButton.Move(Max(630, width - 360))
        this.MainRefreshButton.Move(Max(745, width - 245))
        this.MainPopupButton.Move(Max(845, width - 145))

        this.MainList.Move(, , listWidth, listHeight)
        this.MainStatus.Move(, height - 48, listWidth)
    }


    ShowMain(*) {
        this.MainGui.Show(
            "w" this.Config.MainWidth
            . " h"
            . this.Config.MainHeight
        )

        this.MainSearch.Focus()
    }


    HideMain(*) {
        this.MainGui.Hide()
    }


    ToggleMain(*) {
        if DllCall(
            "user32\IsWindowVisible",
            "Ptr",
            this.MainGui.Hwnd,
            "Int"
        ) {
            this.MainGui.Hide()
        } else {
            this.ShowMain()
        }
    }


    ; =================================================================
    ; POPUP GUI
    ; =================================================================

    BuildPopupGui() {
        this.PopupGui := Gui(
            "+AlwaysOnTop +ToolWindow +Resize +MinSize620x380",
            "Desktop Popup"
        )

        this.PopupGui.SetFont("s10", "Segoe UI")

        this.PopupSearch := this.PopupGui.AddEdit(
            "x10 y10 w500 h28"
        )

        this.SetCueBanner(
            this.PopupSearch,
            "Type to filter the condensed desktop"
        )

        this.PopupFilter := this.PopupGui.AddDropDownList(
            "x520 y10 w175 Choose1",
            [
                "All items",
                "Folders only",
                "Files only",
                "Videos",
                "Programs and Shortcuts",
                "Archives",
                "Desktop root"
            ]
        )

        this.PopupActionsButton := this.PopupGui.AddButton(
            "x705 y10 w75 h28",
            "Actions"
        )

        this.PopupHideButton := this.PopupGui.AddButton(
            "x790 y10 w60 h28",
            "Hide"
        )

        this.PopupList := this.PopupGui.AddListView(
            "x10 y48 w840 h405 Grid FullRowSelect -Multi",
            [
                "Name",
                "Kind",
                "Category",
                "Path"
            ]
        )

        this.PopupStatus := this.PopupGui.AddText(
            "x10 y463 w840 h28 +0x200",
            ""
        )

        this.PopupSearch.OnEvent(
            "Change",
            ObjBindMethod(this, "RefreshPopupList")
        )

        this.PopupFilter.OnEvent(
            "Change",
            ObjBindMethod(this, "RefreshPopupList")
        )

        this.PopupActionsButton.OnEvent(
            "Click",
            ObjBindMethod(this, "ShowPopupActions")
        )

        this.PopupHideButton.OnEvent(
            "Click",
            ObjBindMethod(this, "HidePopup")
        )

        this.PopupList.OnEvent(
            "DoubleClick",
            ObjBindMethod(this, "OnPopupDoubleClick")
        )

        this.PopupList.OnEvent(
            "ContextMenu",
            ObjBindMethod(this, "OnPopupContextMenu")
        )

        this.PopupGui.OnEvent(
            "Size",
            ObjBindMethod(this, "OnPopupResize")
        )

        this.PopupGui.OnEvent(
            "Close",
            ObjBindMethod(this, "HidePopup")
        )

        this.PopupGui.OnEvent(
            "Escape",
            ObjBindMethod(this, "HidePopup")
        )

        this.PopupList.ModifyCol(1, 230)
        this.PopupList.ModifyCol(2, 110)
        this.PopupList.ModifyCol(3, 165)
        this.PopupList.ModifyCol(4, 500)
    }


    OnPopupResize(guiObj, minMax, width, height) {
        if minMax = -1
            return

        searchWidth := Max(220, width - 360)
        listWidth := Max(400, width - 20)
        listHeight := Max(220, height - 115)

        this.PopupSearch.Move(, , searchWidth)
        this.PopupFilter.Move(searchWidth + 20)
        this.PopupActionsButton.Move(width - 155)
        this.PopupHideButton.Move(width - 70)

        this.PopupList.Move(, , listWidth, listHeight)
        this.PopupStatus.Move(, height - 48, listWidth)
    }


    ShowPopup(mode := "All items", *) {
        this.PopupMode := mode
        this.PopupSearch.Value := ""
        this.SelectDropDownText(this.PopupFilter, mode)
        this.RefreshPopupList()

        MouseGetPos(&mouseX, &mouseY)

        popupWidth := this.Config.PopupWidth
        popupHeight := this.Config.PopupHeight

        workArea := this.GetMonitorWorkAreaAtPoint(mouseX, mouseY)

        popupX := mouseX + 8
        popupY := mouseY + 8

        if popupX + popupWidth > workArea.Right
            popupX := workArea.Right - popupWidth

        if popupY + popupHeight > workArea.Bottom
            popupY := workArea.Bottom - popupHeight

        popupX := Max(workArea.Left, popupX)
        popupY := Max(workArea.Top, popupY)

        this.PopupGui.Show(
            "x" popupX
            . " y"
            . popupY
            . " w"
            . popupWidth
            . " h"
            . popupHeight
        )

        this.PopupSearch.Focus()
    }


    HidePopup(*) {
        this.PopupGui.Hide()
    }


    ; =================================================================
    ; INDEXING AND SEARCH
    ; =================================================================

    RefreshEverything(*) {
        this.EnsureCategoryFolders()
        this.BuildIndex()
        this.RefreshMainList()
        this.RefreshPopupList()
        this.BuildTrayMenu()
    }


    BuildIndex() {
        this.Items := []
        seenPaths := Map()

        ; Include every item directly on the user's desktop.
        this.AddDirectoryEntriesToIndex(
            this.Config.DesktopRoot,
            false,
            seenPaths,
            "Desktop root"
        )

        ; Include the contents of the managed category folders recursively.
        for categoryKey, folderName in this.Config.CategoryFolders {
            categoryPath := this.Config.DesktopRoot "\" folderName

            this.AddDirectoryEntriesToIndex(
                categoryPath,
                true,
                seenPaths,
                this.GetDisplayCategoryName(categoryKey)
            )
        }

        if this.Config.IncludePublicDesktop
        && A_DesktopCommon != this.Config.DesktopRoot {
            this.AddDirectoryEntriesToIndex(
                A_DesktopCommon,
                false,
                seenPaths,
                "Public desktop"
            )
        }

        this.SortItemArray(this.Items, 1, false)
    }


    AddDirectoryEntriesToIndex(
        directoryPath,
        recursive,
        seenPaths,
        forcedCategory := ""
    ) {
        if !DirExist(directoryPath)
            return

        mode := recursive ? "FDR" : "FD"

        Loop Files directoryPath "\*", mode {
            if this.Items.Length >= this.Config.MaxIndexedItems
                return

            path := A_LoopFileFullPath
            normalizedPath := StrLower(path)

            if seenPaths.Has(normalizedPath)
                continue

            seenPaths[normalizedPath] := true

            isDirectory := InStr(A_LoopFileAttrib, "D") != 0

            category := forcedCategory

            if category = ""
                category := this.GetLogicalCategory(path, isDirectory)

            this.Items.Push(
                this.CreateIndexedItem(
                    path,
                    isDirectory,
                    category
                )
            )
        }
    }


    CreateIndexedItem(path, isDirectory, category) {
        SplitPath(
            path,
            &name,
            &directory,
            &extension
        )

        sizeBytes := 0
        modifiedRaw := ""

        try modifiedRaw := FileGetTime(path, "M")

        if !isDirectory {
            try sizeBytes := FileGetSize(path)
        }

        kind := isDirectory
            ? "Folder"
            : (extension != "" ? StrUpper(extension) " file" : "File")

        return {
            Name: name,
            Path: path,
            Parent: directory,
            Extension: StrLower(extension),
            IsDirectory: isDirectory,
            Kind: kind,
            Category: category,
            SizeBytes: sizeBytes,
            SizeText: isDirectory ? "" : this.FormatBytes(sizeBytes),
            ModifiedRaw: modifiedRaw,
            ModifiedText: modifiedRaw != ""
                ? FormatTime(modifiedRaw, "yyyy-MM-dd HH:mm")
                : ""
        }
    }


    GetLogicalCategory(path, isDirectory) {
        parent := this.GetParentDirectory(path)

        for categoryKey, folderName in this.Config.CategoryFolders {
            categoryPath := this.Config.DesktopRoot "\" folderName

            if this.PathStartsWith(path, categoryPath)
                return this.GetDisplayCategoryName(categoryKey)
        }

        if this.PathsEqual(parent, this.Config.DesktopRoot)
            return isDirectory ? "Desktop folder" : "Desktop root"

        return isDirectory ? "Folder" : "File"
    }


    GetDisplayCategoryName(categoryKey) {
        switch categoryKey {
            case "Videos":
                return "Videos"
            case "Programs":
                return "Programs and Shortcuts"
            case "Archives":
                return "Archives"
            default:
                return categoryKey
        }
    }


    RefreshMainList(*) {
        query := StrLower(Trim(this.MainSearch.Value))
        filter := this.MainFilter.Text

        visibleCount := this.FillListView(
            this.MainList,
            this.MainRows,
            query,
            filter,
            true
        )

        this.MainStatus.Text :=
            visibleCount
            . " shown / "
            . this.Items.Length
            . " indexed"
            . "    |    Double-click opens"
            . "    |    Right-click shows actions"
    }


    RefreshPopupList(*) {
        query := StrLower(Trim(this.PopupSearch.Value))
        filter := this.PopupFilter.Text

        if filter = ""
            filter := this.PopupMode

        visibleCount := this.FillListView(
            this.PopupList,
            this.PopupRows,
            query,
            filter,
            false
        )

        this.PopupStatus.Text :=
            visibleCount
            . " shown"
            . "    |    Double-click opens"
            . "    |    Right-click shows the action toolbar"
    }


    FillListView(
        listView,
        rowMap,
        query,
        filter,
        includeDetails
    ) {
        listView.Opt("-Redraw")
        listView.Delete()
        rowMap.Clear()

        visibleCount := 0

        for item in this.Items {
            if !this.ItemMatchesFilter(item, filter)
                continue

            if query != "" && !this.ItemMatchesQuery(item, query)
                continue

            if includeDetails {
                rowNumber := listView.Add(
                    "",
                    item.Name,
                    item.Kind,
                    item.Category,
                    item.SizeText,
                    item.ModifiedText,
                    item.Path
                )
            } else {
                rowNumber := listView.Add(
                    "",
                    item.Name,
                    item.Kind,
                    item.Category,
                    item.Path
                )
            }

            rowMap[rowNumber] := item
            visibleCount += 1
        }

        listView.Opt("+Redraw")
        return visibleCount
    }


    ItemMatchesQuery(item, query) {
        haystack := StrLower(
            item.Name
            . "`n"
            . item.Kind
            . "`n"
            . item.Category
            . "`n"
            . item.Path
        )

        return InStr(haystack, query) != 0
    }


    ItemMatchesFilter(item, filter) {
        switch filter {
            case "", "All items":
                return true

            case "Folders only":
                return item.IsDirectory

            case "Files only":
                return !item.IsDirectory

            case "Videos":
                return item.Category = "Videos"

            case "Programs and Shortcuts":
                return item.Category = "Programs and Shortcuts"

            case "Archives":
                return item.Category = "Archives"

            case "Desktop root":
                return this.PathsEqual(
                    item.Parent,
                    this.Config.DesktopRoot
                )

            default:
                return true
        }
    }


    ; =================================================================
    ; LIST INTERACTION
    ; =================================================================

    OnMainSingleClick(listView, rowNumber) {
        if rowNumber <= 0
            return

        item := this.GetRowItem(this.MainRows, rowNumber)

        if !item
            return

        action := this.MainClickAction.Text

        switch action {
            case "Single click: Open":
                if A_TickCount >= this.SuppressSingleClickUntil
                    SetTimer(
                        ObjBindMethod(this, "DeferredOpen").Bind(item.Path),
                        -220
                    )

            case "Single click: Show in Explorer":
                if A_TickCount >= this.SuppressSingleClickUntil
                    this.ShowInExplorer(item.Path)
        }
    }


    DeferredOpen(path, *) {
        if A_TickCount < this.SuppressSingleClickUntil
            return

        if FileExist(path) || DirExist(path)
            this.OpenPath(path)
    }


    OnMainDoubleClick(listView, rowNumber) {
        this.SuppressSingleClickUntil := A_TickCount + 400

        item := this.GetRowItem(this.MainRows, rowNumber)

        if item
            this.OpenPath(item.Path)
    }


    OnPopupDoubleClick(listView, rowNumber) {
        item := this.GetRowItem(this.PopupRows, rowNumber)

        if item
            this.OpenPath(item.Path)
    }


    OnMainContextMenu(listView, rowNumber, isRightClick, x, y) {
        item := this.GetRowItem(
            this.MainRows,
            rowNumber > 0 ? rowNumber : listView.GetNext(0, "F")
        )

        if item
            this.ShowItemActionMenu(item)
    }


    OnPopupContextMenu(listView, rowNumber, isRightClick, x, y) {
        item := this.GetRowItem(
            this.PopupRows,
            rowNumber > 0 ? rowNumber : listView.GetNext(0, "F")
        )

        if item
            this.ShowItemActionMenu(item)
    }


    ShowPopupActions(*) {
        rowNumber := this.PopupList.GetNext(0, "F")
        item := this.GetRowItem(this.PopupRows, rowNumber)

        if !item {
            MsgBox(
                "Select an item first.",
                this.AppTitle,
                "Iconi"
            )
            return
        }

        this.ShowItemActionMenu(item)
    }


    GetRowItem(rowMap, rowNumber) {
        if rowNumber <= 0 || !rowMap.Has(rowNumber)
            return false

        return rowMap[rowNumber]
    }


    OnColumnClick(listView, columnNumber) {
        descending := false

        if columnNumber = this.LastSortColumn
            descending := !this.LastSortDescending

        this.LastSortColumn := columnNumber
        this.LastSortDescending := descending

        this.SortItemArray(
            this.Items,
            columnNumber,
            descending
        )

        this.RefreshMainList()
        this.RefreshPopupList()
    }


    SortItemArray(items, columnNumber, descending) {
        if items.Length < 2
            return

        temporaryItems := []
        temporaryItems.Length := items.Length

        this.MergeSortItemRange(
            items,
            temporaryItems,
            1,
            items.Length,
            columnNumber,
            descending
        )
    }


    MergeSortItemRange(
        items,
        temporaryItems,
        leftIndex,
        rightIndex,
        columnNumber,
        descending
    ) {
        if leftIndex >= rightIndex
            return

        middleIndex := Floor((leftIndex + rightIndex) / 2)

        this.MergeSortItemRange(
            items,
            temporaryItems,
            leftIndex,
            middleIndex,
            columnNumber,
            descending
        )

        this.MergeSortItemRange(
            items,
            temporaryItems,
            middleIndex + 1,
            rightIndex,
            columnNumber,
            descending
        )

        leftCursor := leftIndex
        rightCursor := middleIndex + 1
        outputCursor := leftIndex

        while leftCursor <= middleIndex
        && rightCursor <= rightIndex {
            comparison := this.CompareItems(
                items[leftCursor],
                items[rightCursor],
                columnNumber,
                descending
            )

            if comparison <= 0 {
                temporaryItems[outputCursor] := items[leftCursor]
                leftCursor += 1
            } else {
                temporaryItems[outputCursor] := items[rightCursor]
                rightCursor += 1
            }

            outputCursor += 1
        }

        while leftCursor <= middleIndex {
            temporaryItems[outputCursor] := items[leftCursor]
            leftCursor += 1
            outputCursor += 1
        }

        while rightCursor <= rightIndex {
            temporaryItems[outputCursor] := items[rightCursor]
            rightCursor += 1
            outputCursor += 1
        }

        copyIndex := leftIndex

        while copyIndex <= rightIndex {
            items[copyIndex] := temporaryItems[copyIndex]
            copyIndex += 1
        }
    }


    CompareItems(leftItem, rightItem, columnNumber, descending) {
        result := 0

        switch columnNumber {
            case 1:
                result := StrCompare(leftItem.Name, rightItem.Name, false)

            case 2:
                result := StrCompare(leftItem.Kind, rightItem.Kind, false)

            case 3:
                result := StrCompare(leftItem.Category, rightItem.Category, false)

            case 4:
                result := leftItem.SizeBytes = rightItem.SizeBytes
                    ? 0
                    : (leftItem.SizeBytes > rightItem.SizeBytes ? 1 : -1)

            case 5:
                result := StrCompare(
                    leftItem.ModifiedRaw,
                    rightItem.ModifiedRaw,
                    false
                )

            case 6:
                result := StrCompare(leftItem.Path, rightItem.Path, false)

            default:
                result := StrCompare(leftItem.Name, rightItem.Name, false)
        }

        return descending ? -result : result
    }


    ; =================================================================
    ; ITEM ACTION MENU
    ; =================================================================

    ShowItemActionMenu(item) {
        actionMenu := Menu()

        actionMenu.Add(
            item.IsDirectory ? "Open Folder" : "Open",
            ObjBindMethod(this, "OpenPath").Bind(item.Path)
        )

        if !item.IsDirectory {
            actionMenu.Add(
                "Open With...",
                ObjBindMethod(this, "OpenWith").Bind(item.Path)
            )
        }

        actionMenu.Add(
            "Show in File Explorer",
            ObjBindMethod(this, "ShowInExplorer").Bind(item.Path)
        )

        if !item.IsDirectory
        && this.CanRunAsAdministrator(item.Extension) {
            actionMenu.Add(
                "Run as Administrator",
                ObjBindMethod(this, "RunAsAdministrator").Bind(item.Path)
            )
        }

        actionMenu.Add()

        actionMenu.Add(
            "Copy",
            ObjBindMethod(this, "CopyShellItem").Bind(item.Path)
        )

        actionMenu.Add(
            "Cut",
            ObjBindMethod(this, "CutShellItem").Bind(item.Path)
        )

        actionMenu.Add(
            "Copy Full Path",
            ObjBindMethod(this, "CopyFullPath").Bind(item.Path)
        )

        if item.IsDirectory {
            actionMenu.Add(
                "Paste Into This Folder",
                ObjBindMethod(this, "PasteIntoFolder").Bind(item.Path)
            )

            actionMenu.Add(
                "Create New Folder Here",
                ObjBindMethod(this, "CreateFolderInside").Bind(item.Path)
            )
        }

        actionMenu.Add()

        actionMenu.Add(
            "Rename",
            ObjBindMethod(this, "RenameItem").Bind(item.Path)
        )

        actionMenu.Add(
            "Create Desktop Shortcut",
            ObjBindMethod(this, "CreateDesktopShortcut").Bind(item.Path)
        )

        if !item.IsDirectory {
            moveMenu := Menu()

            moveMenu.Add(
                "Desktop Root",
                ObjBindMethod(this, "MoveItemToDirectory").Bind(
                    item.Path,
                    this.Config.DesktopRoot
                )
            )

            moveMenu.Add()

            for categoryKey, folderName in this.Config.CategoryFolders {
                destinationDirectory :=
                    this.Config.DesktopRoot
                    . "\"
                    . folderName

                moveMenu.Add(
                    folderName,
                    ObjBindMethod(this, "MoveItemToDirectory").Bind(
                        item.Path,
                        destinationDirectory
                    )
                )
            }

            actionMenu.Add("Move To", moveMenu)
        }

        actionMenu.Add()

        actionMenu.Add(
            "Delete to Recycle Bin",
            ObjBindMethod(this, "RecycleItem").Bind(item.Path)
        )

        actionMenu.Add(
            "Properties",
            ObjBindMethod(this, "ShowProperties").Bind(item.Path)
        )

        actionMenu.Add()

        actionMenu.Add(
            "Refresh Condensed Desktop",
            ObjBindMethod(this, "RefreshEverything")
        )

        actionMenu.Show()
    }


    OpenPath(path, *) {
        if !FileExist(path) && !DirExist(path) {
            this.NotifyMissingPath(path)
            return
        }

        try {
            Run(path)
        } catch Error as err {
            MsgBox(
                "Could not open:`n" path "`n`n" err.Message,
                this.AppTitle,
                "IconX"
            )
        }
    }


    OpenWith(path, *) {
        if !FileExist(path) {
            this.NotifyMissingPath(path)
            return
        }

        try {
            Run(
                'rundll32.exe shell32.dll,OpenAs_RunDLL "'
                . path
                . '"'
            )
        } catch Error as err {
            MsgBox(
                "Could not display Open With.`n`n" err.Message,
                this.AppTitle,
                "IconX"
            )
        }
    }


    ShowInExplorer(path, *) {
        if !FileExist(path) && !DirExist(path) {
            this.NotifyMissingPath(path)
            return
        }

        try {
            Run(
                'explorer.exe /select,"'
                . path
                . '"'
            )
        } catch Error as err {
            MsgBox(
                "Could not open File Explorer.`n`n" err.Message,
                this.AppTitle,
                "IconX"
            )
        }
    }


    RunAsAdministrator(path, *) {
        if !FileExist(path) {
            this.NotifyMissingPath(path)
            return
        }

        workingDirectory := this.GetParentDirectory(path)

        result := DllCall(
            "shell32\ShellExecuteW",
            "Ptr", 0,
            "Str", "runas",
            "Str", path,
            "Ptr", 0,
            "Str", workingDirectory,
            "Int", 1,
            "Ptr"
        )

        if result <= 32 {
            MsgBox(
                "Windows could not run the item as administrator.`n"
                . "ShellExecute result: "
                . result,
                this.AppTitle,
                "IconX"
            )
        }
    }


    CanRunAsAdministrator(extension) {
        return InStr(
            ",exe,com,bat,cmd,ps1,lnk,msi,",
            "," extension ",",
            false
        ) != 0
    }


    CopyShellItem(path, *) {
        if this.SetShellClipboard(path, false) {
            TrayTip(
                "Copied",
                this.GetLeafName(path),
                1
            )
        }
    }


    CutShellItem(path, *) {
        if this.SetShellClipboard(path, true) {
            TrayTip(
                "Cut",
                this.GetLeafName(path),
                1
            )
        }
    }


    SetShellClipboard(path, cutOperation) {
        static CF_HDROP := 15
        static GMEM_MOVEABLE := 0x0002
        static GMEM_ZEROINIT := 0x0040
        static DROPEFFECT_COPY := 1
        static DROPEFFECT_MOVE := 2

        if !FileExist(path) && !DirExist(path) {
            this.NotifyMissingPath(path)
            return false
        }

        if !DllCall("user32\OpenClipboard", "Ptr", 0, "Int") {
            MsgBox(
                "The Windows clipboard is currently unavailable.",
                this.AppTitle,
                "Icon!"
            )
            return false
        }

        dropHandle := 0
        effectHandle := 0
        dropTransferred := false
        effectTransferred := false

        try {
            DllCall("user32\EmptyClipboard", "Int")

            characterCount := StrPut(path, "UTF-16")
            totalBytes := 20 + ((characterCount + 1) * 2)

            dropHandle := DllCall(
                "kernel32\GlobalAlloc",
                "UInt", GMEM_MOVEABLE | GMEM_ZEROINIT,
                "UPtr", totalBytes,
                "Ptr"
            )

            if !dropHandle
                throw OSError(A_LastError, "GlobalAlloc failed for CF_HDROP.")

            dropPointer := DllCall(
                "kernel32\GlobalLock",
                "Ptr", dropHandle,
                "Ptr"
            )

            if !dropPointer
                throw OSError(A_LastError, "GlobalLock failed for CF_HDROP.")

            NumPut("UInt", 20, dropPointer, 0)
            NumPut("Int", 1, dropPointer, 16)
            StrPut(path, dropPointer + 20, characterCount, "UTF-16")

            DllCall(
                "kernel32\GlobalUnlock",
                "Ptr", dropHandle
            )

            if !DllCall(
                "user32\SetClipboardData",
                "UInt", CF_HDROP,
                "Ptr", dropHandle,
                "Ptr"
            ) {
                throw OSError(A_LastError, "SetClipboardData failed for CF_HDROP.")
            }

            dropTransferred := true

            preferredDropEffectFormat := DllCall(
                "user32\RegisterClipboardFormatW",
                "Str", "Preferred DropEffect",
                "UInt"
            )

            effectHandle := DllCall(
                "kernel32\GlobalAlloc",
                "UInt", GMEM_MOVEABLE | GMEM_ZEROINIT,
                "UPtr", 4,
                "Ptr"
            )

            if !effectHandle
                throw OSError(A_LastError, "GlobalAlloc failed for drop effect.")

            effectPointer := DllCall(
                "kernel32\GlobalLock",
                "Ptr", effectHandle,
                "Ptr"
            )

            if !effectPointer
                throw OSError(A_LastError, "GlobalLock failed for drop effect.")

            NumPut(
                "UInt",
                cutOperation ? DROPEFFECT_MOVE : DROPEFFECT_COPY,
                effectPointer,
                0
            )

            DllCall(
                "kernel32\GlobalUnlock",
                "Ptr", effectHandle
            )

            if !DllCall(
                "user32\SetClipboardData",
                "UInt", preferredDropEffectFormat,
                "Ptr", effectHandle,
                "Ptr"
            ) {
                throw OSError(
                    A_LastError,
                    "SetClipboardData failed for Preferred DropEffect."
                )
            }

            effectTransferred := true
            return true
        } catch Error as err {
            MsgBox(
                "Could not place the item on the shell clipboard.`n`n"
                . err.Message,
                this.AppTitle,
                "IconX"
            )
            return false
        } finally {
            DllCall("user32\CloseClipboard", "Int")

            if dropHandle && !dropTransferred {
                DllCall(
                    "kernel32\GlobalFree",
                    "Ptr", dropHandle,
                    "Ptr"
                )
            }

            if effectHandle && !effectTransferred {
                DllCall(
                    "kernel32\GlobalFree",
                    "Ptr", effectHandle,
                    "Ptr"
                )
            }
        }
    }


    CopyFullPath(path, *) {
        A_Clipboard := path

        TrayTip(
            "Path copied",
            path,
            1
        )
    }


    PasteIntoFolder(folderPath, *) {
        if !DirExist(folderPath) {
            this.NotifyMissingPath(folderPath)
            return
        }

        try {
            shellApplication := ComObject("Shell.Application")
            destinationFolder := shellApplication.NameSpace(folderPath)

            if !destinationFolder
                throw Error("Windows Shell could not open the destination folder.")

            destinationFolder.Self.InvokeVerb("paste")

            ; Shell paste operations are asynchronous. Refresh after Explorer
            ; has had time to begin processing the clipboard operation.
            SetTimer(
                ObjBindMethod(this, "RefreshEverything"),
                -1200
            )
        } catch Error as err {
            MsgBox(
                "Could not paste into the folder.`n`n" err.Message,
                this.AppTitle,
                "IconX"
            )
        }
    }


    CreateFolderInside(parentFolder, *) {
        if !DirExist(parentFolder) {
            this.NotifyMissingPath(parentFolder)
            return
        }

        result := InputBox(
            "Enter the new folder name:",
            "Create Folder",
            "w500 h145",
            "New Folder"
        )

        if result.Result != "OK"
            return

        folderName := Trim(result.Value)

        if folderName = ""
            return

        if RegExMatch(folderName, '[<>:"/\\|?*]') {
            MsgBox(
                "The folder name contains a character Windows does not allow.",
                this.AppTitle,
                "Icon!"
            )
            return
        }

        folderPath := this.GetUniqueDestinationPath(
            parentFolder,
            folderName
        )

        try {
            DirCreate(folderPath)
            this.RefreshEverything()
        } catch Error as err {
            MsgBox(
                "Could not create the folder.`n`n" err.Message,
                this.AppTitle,
                "IconX"
            )
        }
    }


    RenameItem(path, *) {
        if !FileExist(path) && !DirExist(path) {
            this.NotifyMissingPath(path)
            return
        }

        oldName := this.GetLeafName(path)

        result := InputBox(
            "Enter the new name:",
            "Rename",
            "w520 h145",
            oldName
        )

        if result.Result != "OK"
            return

        newName := Trim(result.Value)

        if newName = "" || newName = oldName
            return

        if RegExMatch(newName, '[<>:"/\\|?*]') {
            MsgBox(
                "The name contains a character Windows does not allow.",
                this.AppTitle,
                "Icon!"
            )
            return
        }

        newPath := this.GetParentDirectory(path) "\" newName

        if FileExist(newPath) || DirExist(newPath) {
            MsgBox(
                "An item with that name already exists.",
                this.AppTitle,
                "Icon!"
            )
            return
        }

        try {
            if DirExist(path)
                DirMove(path, newPath)
            else
                FileMove(path, newPath)

            this.RefreshEverything()
        } catch Error as err {
            MsgBox(
                "Rename failed.`n`n" err.Message,
                this.AppTitle,
                "IconX"
            )
        }
    }


    CreateDesktopShortcut(path, *) {
        if !FileExist(path) && !DirExist(path) {
            this.NotifyMissingPath(path)
            return
        }

        baseName := this.GetLeafName(path)

        if !DirExist(path)
            baseName := RegExReplace(baseName, "\.[^.]+$")

        shortcutPath := this.GetUniqueDestinationPath(
            this.Config.DesktopRoot,
            baseName ".lnk"
        )

        try {
            FileCreateShortcut(
                path,
                shortcutPath,
                this.GetParentDirectory(path)
            )

            this.RefreshEverything()

            TrayTip(
                "Shortcut created",
                this.GetLeafName(shortcutPath),
                1
            )
        } catch Error as err {
            MsgBox(
                "Could not create the shortcut.`n`n" err.Message,
                this.AppTitle,
                "IconX"
            )
        }
    }


    MoveItemToDirectory(path, destinationDirectory, *) {
        if !FileExist(path) && !DirExist(path) {
            this.NotifyMissingPath(path)
            return
        }

        try {
            destinationPath := this.MoveItemPreservingName(
                path,
                destinationDirectory
            )

            if destinationPath = "" {
                TrayTip(
                    "No move needed",
                    "The item is already in that folder.",
                    1
                )
                return
            }

            this.RefreshEverything()

            TrayTip(
                "Moved",
                this.GetLeafName(destinationPath),
                1
            )
        } catch Error as err {
            MsgBox(
                "Move failed.`n`n" err.Message,
                this.AppTitle,
                "IconX"
            )
        }
    }


    RecycleItem(path, *) {
        if !FileExist(path) && !DirExist(path) {
            this.NotifyMissingPath(path)
            return
        }

        answer := MsgBox(
            "Move this item to the Recycle Bin?`n`n"
            . path,
            this.AppTitle,
            "YesNo Icon!"
        )

        if answer != "Yes"
            return

        try {
            FileRecycle(path)
            this.RefreshEverything()
        } catch Error as err {
            MsgBox(
                "Delete failed.`n`n" err.Message,
                this.AppTitle,
                "IconX"
            )
        }
    }


    ShowProperties(path, *) {
        if !FileExist(path) && !DirExist(path) {
            this.NotifyMissingPath(path)
            return
        }

        static SHOP_FILEPATH := 0x00000002

        result := DllCall(
            "shell32\SHObjectProperties",
            "Ptr", 0,
            "UInt", SHOP_FILEPATH,
            "Str", path,
            "Ptr", 0,
            "Int"
        )

        if !result {
            MsgBox(
                "Windows could not display the item properties.",
                this.AppTitle,
                "Icon!"
            )
        }
    }


    NotifyMissingPath(path) {
        MsgBox(
            "The item no longer exists at:`n`n"
            . path
            . "`n`nThe condensed desktop will now refresh.",
            this.AppTitle,
            "Icon!"
        )

        this.RefreshEverything()
    }


    ; =================================================================
    ; TRAY AND FOLDER MENUS
    ; =================================================================

    BuildTrayMenu(*) {
        A_TrayMenu.Delete()

        A_TrayMenu.Add(
            "Show Condensed Desktop",
            ObjBindMethod(this, "ShowMain")
        )

        A_TrayMenu.Add(
            "Show All-Items Popup",
            ObjBindMethod(this, "ShowPopup").Bind("All items")
        )

        A_TrayMenu.Add(
            "Show Folders Popup",
            ObjBindMethod(this, "ShowPopup").Bind("Folders only")
        )

        folderMenu := this.BuildFolderSubmenu()
        A_TrayMenu.Add("Desktop Folders", folderMenu)

        A_TrayMenu.Add()

        A_TrayMenu.Add(
            "Organize New Desktop Items",
            ObjBindMethod(this, "OrganizeDesktopFiles").Bind(true)
        )

        A_TrayMenu.Add(
            "Undo Last Organization",
            ObjBindMethod(this, "UndoLastOrganization")
        )

        A_TrayMenu.Add(
            "Open Desktop",
            ObjBindMethod(this, "OpenPath").Bind(this.Config.DesktopRoot)
        )

        A_TrayMenu.Add(
            "Open Organizer Logs",
            ObjBindMethod(this, "OpenPath").Bind(this.LogDirectory)
        )

        A_TrayMenu.Add(
            "Refresh Index",
            ObjBindMethod(this, "RefreshEverything")
        )

        A_TrayMenu.Add()

        A_TrayMenu.Add(
            "Reload Script",
            (*) => Reload()
        )

        A_TrayMenu.Add(
            "Exit",
            (*) => ExitApp()
        )

        A_TrayMenu.Default := "Show Condensed Desktop"
        A_IconTip := this.AppTitle
    }


    BuildFolderSubmenu() {
        folderMenu := Menu()
        usedCaptions := Map()

        ; Managed folders always appear first.
        for categoryKey, folderName in this.Config.CategoryFolders {
            folderPath := this.Config.DesktopRoot "\" folderName
            caption := this.GetUniqueMenuCaption(folderName, usedCaptions)

            folderMenu.Add(
                caption,
                ObjBindMethod(this, "OpenPath").Bind(folderPath)
            )
        }

        folderMenu.Add()

        rootFolderCount := 0

        Loop Files this.Config.DesktopRoot "\*", "D" {
            folderPath := A_LoopFileFullPath
            folderName := A_LoopFileName

            if this.IsManagedCategoryFolder(folderPath)
                continue

            caption := this.GetUniqueMenuCaption(folderName, usedCaptions)

            folderMenu.Add(
                caption,
                ObjBindMethod(this, "OpenPath").Bind(folderPath)
            )

            rootFolderCount += 1
        }

        if rootFolderCount = 0
            folderMenu.Add("(No additional desktop folders)", (*) => 0)

        folderMenu.Add()
        folderMenu.Add(
            "Search and Right-Click Folders...",
            ObjBindMethod(this, "ShowPopup").Bind("Folders only")
        )

        return folderMenu
    }


    GetUniqueMenuCaption(caption, usedCaptions) {
        originalCaption := caption
        counter := 2

        while usedCaptions.Has(StrLower(caption)) {
            caption := originalCaption " (" counter ")"
            counter += 1
        }

        usedCaptions[StrLower(caption)] := true
        return caption
    }


    IsManagedCategoryFolder(path) {
        for categoryKey, folderName in this.Config.CategoryFolders {
            managedPath := this.Config.DesktopRoot "\" folderName

            if this.PathsEqual(path, managedPath)
                return true
        }

        return false
    }


    ; =================================================================
    ; DRAG AND DROP
    ; =================================================================

    OnDropFiles(guiObj, guiCtrl, fileArray, x, y) {
        if fileArray.Length = 0
            return

        destinationMenu := Menu()

        destinationMenu.Add(
            "Desktop Root",
            ObjBindMethod(this, "MoveDroppedItems").Bind(
                fileArray,
                this.Config.DesktopRoot
            )
        )

        destinationMenu.Add()

        for categoryKey, folderName in this.Config.CategoryFolders {
            destinationMenu.Add(
                folderName,
                ObjBindMethod(this, "MoveDroppedItems").Bind(
                    fileArray,
                    this.Config.DesktopRoot "\" folderName
                )
            )
        }

        destinationMenu.Show()
    }


    MoveDroppedItems(fileArray, destinationDirectory, *) {
        moved := 0
        failed := 0

        for sourcePath in fileArray {
            try {
                destinationPath := this.MoveItemPreservingName(
                    sourcePath,
                    destinationDirectory
                )

                if destinationPath != ""
                    moved += 1
            } catch {
                failed += 1
            }
        }

        this.RefreshEverything()

        MsgBox(
            "Dropped-item move completed.`n`n"
            . "Moved: " moved "`n"
            . "Failed: " failed,
            this.AppTitle,
            failed > 0 ? "Icon!" : "Iconi"
        )
    }


    ; =================================================================
    ; GENERAL HELPERS
    ; =================================================================

    SelectDropDownText(dropDown, desiredText) {
        ; Setting Text selects the item whose full text matches.
        try {
            dropDown.Text := desiredText
        } catch {
            dropDown.Choose(1)
        }
    }


    SetCueBanner(editControl, text) {
        static EM_SETCUEBANNER := 0x1501

        characterCount := StrPut(text, "UTF-16")
        textBuffer := Buffer(characterCount * 2, 0)
        StrPut(text, textBuffer, characterCount, "UTF-16")

        DllCall(
            "user32\SendMessageW",
            "Ptr", editControl.Hwnd,
            "UInt", EM_SETCUEBANNER,
            "Ptr", 1,
            "Ptr", textBuffer.Ptr,
            "Ptr"
        )
    }


    GetMonitorWorkAreaAtPoint(x, y) {
        monitorCount := MonitorGetCount()

        Loop monitorCount {
            monitorNumber := A_Index

            MonitorGetWorkArea(
                monitorNumber,
                &left,
                &top,
                &right,
                &bottom
            )

            if x >= left
            && x < right
            && y >= top
            && y < bottom {
                return {
                    Left: left,
                    Top: top,
                    Right: right,
                    Bottom: bottom
                }
            }
        }

        MonitorGetWorkArea(
            1,
            &left,
            &top,
            &right,
            &bottom
        )

        return {
            Left: left,
            Top: top,
            Right: right,
            Bottom: bottom
        }
    }


    GetUniqueDestinationPath(destinationDirectory, leafName) {
        candidatePath := destinationDirectory "\" leafName

        if !FileExist(candidatePath) && !DirExist(candidatePath)
            return candidatePath

        SplitPath(
            leafName,
            &name,
            ,
            &extension,
            &nameWithoutExtension
        )

        counter := 2

        Loop {
            if extension != "" {
                candidateName :=
                    nameWithoutExtension
                    . " ("
                    . counter
                    . ")."
                    . extension
            } else {
                candidateName :=
                    name
                    . " ("
                    . counter
                    . ")"
            }

            candidatePath := destinationDirectory "\" candidateName

            if !FileExist(candidatePath)
            && !DirExist(candidatePath) {
                return candidatePath
            }

            counter += 1
        }
    }


    GetExtension(path) {
        SplitPath(path, , , &extension)
        return StrLower(extension)
    }


    GetLeafName(path) {
        SplitPath(path, &leafName)
        return leafName
    }


    GetParentDirectory(path) {
        SplitPath(path, , &directory)
        return directory
    }


    NormalizePath(path) {
        normalized := StrReplace(path, "/", "\")
        normalized := RTrim(normalized, "\")

        return StrLower(normalized)
    }


    PathsEqual(leftPath, rightPath) {
        return this.NormalizePath(leftPath)
            = this.NormalizePath(rightPath)
    }


    PathStartsWith(path, parentPath) {
        normalizedPath := this.NormalizePath(path)
        normalizedParent := this.NormalizePath(parentPath)

        return normalizedPath = normalizedParent
            || InStr(
                normalizedPath,
                normalizedParent "\",
                false
            ) = 1
    }


    FormatBytes(byteCount) {
        if byteCount < 1024
            return byteCount " B"

        if byteCount < 1024 ** 2
            return Round(byteCount / 1024, 1) " KB"

        if byteCount < 1024 ** 3
            return Round(byteCount / (1024 ** 2), 1) " MB"

        if byteCount < 1024 ** 4
            return Round(byteCount / (1024 ** 3), 2) " GB"

        return Round(byteCount / (1024 ** 4), 2) " TB"
    }
}


; =====================================================================
; APPLICATION INSTANCE AND GLOBAL HOTKEYS
; =====================================================================

global DesktopApp := CondensedDesktopApp()

^!d::DesktopApp.ToggleMain()
^!p::DesktopApp.ShowPopup("All items")
^!f::DesktopApp.ShowPopup("Folders only")
^!o::DesktopApp.OrganizeDesktopFiles(true)
^!z::DesktopApp.UndoLastOrganization()
