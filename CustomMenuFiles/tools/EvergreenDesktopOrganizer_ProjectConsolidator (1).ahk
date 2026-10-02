#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; =====================================================================
; Evergreen Desktop Organizer + Project Consolidator
; AutoHotkey v2
;
; Built for a Desktop full of:
; - ChatGPT full project ZIPs
; - extracted iterative project folders
; - loose images/docs/code/videos/archive files
;
; It does these jobs:
; 1. Organize loose Desktop files into filetype folders.
; 2. Report anything left over.
; 3. Consolidate iterative Python project folders/ZIPs into:
;       Desktop\Consolidated_Python_Projects
;    with current/newest project files front and older sources archived.
;
; Lossless:
; - Original extracted project folders are copied, not deleted.
; - Source ZIPs are copied into _source_zips and then can also be organized.
; - Existing destination names are never overwritten.
;
; Hotkeys:
;   Ctrl+Alt+O  Organize all loose Desktop files by file type
;   Ctrl+Alt+C  Consolidate Python project iterations from Desktop
;   Ctrl+Alt+A  Run both: consolidate projects, then organize loose files
;   Ctrl+Alt+R  Open latest report folder
;   Ctrl+Alt+M  Show action menu
; =====================================================================

global APP_TITLE := "Evergreen Desktop Organizer + Project Consolidator"

global CONFIG := {
    DesktopRoot: A_Desktop,
    ConsolidatedRoot: A_Desktop "\Consolidated_Python_Projects",
    ReportsRoot: A_Desktop "\Desktop - Organization Reports",
    MaxProjectScanDepth: 6,

    CategoryFolders: Map(
        "Images", "Desktop - Images",
        "Videos", "Desktop - Videos",
        "Audio", "Desktop - Audio",
        "Code", "Desktop - Code Files",
        "Documents", "Desktop - Documents",
        "Spreadsheets", "Desktop - Spreadsheets",
        "Presentations", "Desktop - Presentations",
        "Archives", "Desktop - Archives",
        "ProjectZips", "Desktop - Project Source Zips",
        "Installers", "Desktop - Installers",
        "Programs", "Desktop - Shortcuts and Programs",
        "Data", "Desktop - Data Files",
        "Fonts", "Desktop - Fonts",
        "Cad3D", "Desktop - 3D CAD",
        "Misc", "Desktop - Misc Unsorted"
    ),

    ExcludedFolderNames: Map(
        ".git", true,
        ".hg", true,
        ".svn", true,
        "__pycache__", true,
        ".mypy_cache", true,
        ".pytest_cache", true,
        ".ruff_cache", true,
        ".tox", true,
        ".nox", true,
        ".venv", true,
        "venv", true,
        "env", true,
        "node_modules", true,
        "site-packages", true,
        "dist-packages", true,
        "build", true,
        "dist", true,
        "globalcoder1", true,
        "Consolidated_Python_Projects", true,
        "Desktop - Images", true,
        "Desktop - Videos", true,
        "Desktop - Audio", true,
        "Desktop - Code Files", true,
        "Desktop - Documents", true,
        "Desktop - Spreadsheets", true,
        "Desktop - Presentations", true,
        "Desktop - Archives", true,
        "Desktop - Project Source Zips", true,
        "Desktop - Installers", true,
        "Desktop - Shortcuts and Programs", true,
        "Desktop - Data Files", true,
        "Desktop - Fonts", true,
        "Desktop - 3D CAD", true,
        "Desktop - Misc Unsorted", true,
        "Desktop - Organization Reports", true
    )
}


class EvergreenDesktopOrganizer {
    __New() {
        this.Config := CONFIG
        this.LastReportPath := ""
        this.EnsureFolders()
        this.BuildTrayMenu()
    }

    EnsureFolders() {
        DirCreate(this.Config.ConsolidatedRoot)
        DirCreate(this.Config.ReportsRoot)
        for key, folder in this.Config.CategoryFolders
            DirCreate(this.Config.DesktopRoot "\" folder)
    }

    BuildTrayMenu(*) {
        A_TrayMenu.Delete()
        A_TrayMenu.Add("Run Full Evergreen Automation", ObjBindMethod(this, "RunFullAutomation"))
        A_TrayMenu.Add("Consolidate Python Project Iterations", ObjBindMethod(this, "ConsolidateProjects"))
        A_TrayMenu.Add("Organize Loose Desktop Files", ObjBindMethod(this, "OrganizeLooseDesktopFiles"))
        A_TrayMenu.Add()
        A_TrayMenu.Add("Open Consolidated Projects", ObjBindMethod(this, "OpenPath").Bind(this.Config.ConsolidatedRoot))
        A_TrayMenu.Add("Open Reports", ObjBindMethod(this, "OpenPath").Bind(this.Config.ReportsRoot))
        A_TrayMenu.Add("Open Desktop", ObjBindMethod(this, "OpenPath").Bind(this.Config.DesktopRoot))
        A_TrayMenu.Add()
        A_TrayMenu.Add("Reload Script", (*) => Reload())
        A_TrayMenu.Add("Exit", (*) => ExitApp())
        A_TrayMenu.Default := "Run Full Evergreen Automation"
        A_IconTip := APP_TITLE
    }

    ShowActionMenu(*) {
        menu := Menu()
        menu.Add("Run Full Evergreen Automation", ObjBindMethod(this, "RunFullAutomation"))
        menu.Add("Consolidate Python Project Iterations", ObjBindMethod(this, "ConsolidateProjects"))
        menu.Add("Organize Loose Desktop Files", ObjBindMethod(this, "OrganizeLooseDesktopFiles"))
        menu.Add()
        menu.Add("Open Consolidated Projects", ObjBindMethod(this, "OpenPath").Bind(this.Config.ConsolidatedRoot))
        menu.Add("Open Reports", ObjBindMethod(this, "OpenPath").Bind(this.Config.ReportsRoot))
        menu.Show()
    }

    RunFullAutomation(*) {
        answer := MsgBox(
            "Run full Desktop automation now?`n`n"
            . "1. Consolidate iterative Python project folders/ZIPs.`n"
            . "2. Organize all loose Desktop files by type.`n"
            . "3. Write reports.`n`n"
            . "Original project folders are not deleted. Existing files are not overwritten.",
            APP_TITLE,
            "YesNo Icon?"
        )
        if answer != "Yes"
            return

        projectReport := this.ConsolidateProjects(false)
        organizeReport := this.OrganizeLooseDesktopFiles(false)
        MsgBox(
            "Full automation completed.`n`n"
            . "Project report:`n" projectReport "`n`n"
            . "Organizer report:`n" organizeReport,
            APP_TITLE,
            "Iconi"
        )
    }

    OrganizeLooseDesktopFiles(showMessage := true, *) {
        this.EnsureFolders()
        moved := []
        leftovers := []

        Loop Files this.Config.DesktopRoot "\*", "F" {
            source := A_LoopFileFullPath

            if this.PathsEqual(source, A_ScriptFullPath)
                continue

            categoryKey := this.GetCategoryKeyForFile(source)
            if categoryKey = "" {
                categoryKey := "Misc"
                leftovers.Push(source)
            }

            destDir := this.Config.DesktopRoot "\" this.Config.CategoryFolders[categoryKey]
            try {
                dest := this.MoveItemPreservingName(source, destDir)
                if dest != ""
                    moved.Push({From: source, To: dest, Category: categoryKey})
            } catch Error as err {
                leftovers.Push(source " :: MOVE ERROR: " err.Message)
            }
        }

        report := this.WriteOrganizerReport(moved, leftovers)

        if showMessage {
            MsgBox(
                "Loose Desktop organization complete.`n`n"
                . "Moved: " moved.Length "`n"
                . "Leftover/unclassified moved to Misc/report: " leftovers.Length "`n`n"
                . "Report:`n" report,
                APP_TITLE,
                "Iconi"
            )
        }

        return report
    }

    GetCategoryKeyForFile(path) {
        ext := this.GetExtension(path)

        if ext = ""
            return ""

        images := ",jpg,jpeg,png,gif,bmp,tif,tiff,webp,heic,svg,ico,avif,"
        videos := ",mp4,mkv,avi,mov,wmv,m4v,webm,mpeg,mpg,mts,m2ts,ts,flv,vob,ogv,3gp,"
        audio := ",mp3,wav,flac,aac,m4a,ogg,wma,opus,mid,midi,"
        code := ",py,pyw,ahk,js,ts,tsx,jsx,html,css,scss,json,yaml,yml,toml,ini,cfg,bat,cmd,ps1,sh,sql,cs,cpp,c,h,hpp,java,go,rs,php,rb,lua,xml,"
        docs := ",pdf,doc,docx,rtf,odt,txt,md,epub,mobi,"
        sheets := ",xls,xlsx,xlsm,csv,tsv,ods,"
        slides := ",ppt,pptx,odp,"
        archives := ",7z,rar,tar,gz,gzip,bz2,xz,tgz,cab,iso,"
        installers := ",msi,msix,appx,appxbundle,deb,rpm,dmg,pkg,"
        programs := ",lnk,url,website,exe,com,"
        data := ",db,sqlite,sqlite3,duckdb,parquet,feather,pkl,pickle,jsonl,ndjson,log,"
        fonts := ",ttf,otf,woff,woff2,fon,"
        cad := ",stl,obj,fbx,glb,gltf,step,stp,iges,igs,dwg,dxf,blend,3mf,"

        if ext = "zip"
            return "ProjectZips"
        if InStr(images, "," ext ",")
            return "Images"
        if InStr(videos, "," ext ",")
            return "Videos"
        if InStr(audio, "," ext ",")
            return "Audio"
        if InStr(code, "," ext ",")
            return "Code"
        if InStr(docs, "," ext ",")
            return "Documents"
        if InStr(sheets, "," ext ",")
            return "Spreadsheets"
        if InStr(slides, "," ext ",")
            return "Presentations"
        if InStr(archives, "," ext ",")
            return "Archives"
        if InStr(installers, "," ext ",")
            return "Installers"
        if InStr(programs, "," ext ",")
            return "Programs"
        if InStr(data, "," ext ",")
            return "Data"
        if InStr(fonts, "," ext ",")
            return "Fonts"
        if InStr(cad, "," ext ",")
            return "Cad3D"

        return ""
    }

    ConsolidateProjects(showMessage := true, *) {
        this.EnsureFolders()

        sources := this.FindProjectSources()
        families := this.GroupProjectSources(sources)
        created := []
        errors := []

        for familyKey, family in families {
            try {
                dest := this.ConsolidateFamily(familyKey, family)
                if dest != ""
                    created.Push(dest)
            } catch Error as err {
                errors.Push(familyKey ": " err.Message)
            }
        }

        report := this.WriteProjectReport(sources, families, created, errors)

        if showMessage {
            MsgBox(
                "Project consolidation complete.`n`n"
                . "Project sources found: " sources.Length "`n"
                . "Families created: " created.Length "`n"
                . "Errors: " errors.Length "`n`n"
                . "Report:`n" report,
                APP_TITLE,
                errors.Length > 0 ? "Icon!" : "Iconi"
            )
        }

        return report
    }

    FindProjectSources() {
        sources := []

        Loop Files this.Config.DesktopRoot "\*", "D" {
            folder := A_LoopFileFullPath
            if this.ShouldSkipFolder(folder)
                continue

            pyCount := this.CountPythonFiles(folder, this.Config.MaxProjectScanDepth)
            if pyCount > 0 {
                sources.Push({
                    Path: folder,
                    Name: A_LoopFileName,
                    Type: "folder",
                    FamilyKey: this.GetFamilyKey(A_LoopFileName),
                    PyCount: pyCount,
                    Modified: this.GetNewestModifiedTime(folder)
                })
            }
        }

        Loop Files this.Config.DesktopRoot "\*.zip", "F" {
            zipPath := A_LoopFileFullPath
            pyCount := this.CountPythonFilesInZip(zipPath)
            if pyCount > 0 {
                sources.Push({
                    Path: zipPath,
                    Name: RegExReplace(A_LoopFileName, "\.zip$", ""),
                    Type: "zip",
                    FamilyKey: this.GetFamilyKey(A_LoopFileName),
                    PyCount: pyCount,
                    Modified: FileGetTime(zipPath, "M")
                })
            }
        }

        return sources
    }

    GroupProjectSources(sources) {
        families := Map()

        for src in sources {
            chosen := src.FamilyKey

            for existingKey, family in families {
                if this.FamilyKeysSimilar(src.FamilyKey, existingKey) {
                    chosen := existingKey
                    break
                }
            }

            if !families.Has(chosen)
                families[chosen] := []

            families[chosen].Push(src)
        }

        return families
    }

    FamilyKeysSimilar(a, b) {
        if a = b
            return true
        if StrLen(a) >= 8 && InStr(b, a)
            return true
        if StrLen(b) >= 8 && InStr(a, b)
            return true

        ; Lightweight similarity: compare first 12 cleaned characters.
        return SubStr(a, 1, 12) = SubStr(b, 1, 12)
    }

    ConsolidateFamily(familyKey, family) {
        if family.Length = 0
            return ""

        current := this.ChooseCurrentSource(family)
        displayName := this.SafeName(this.TitleCase(StrReplace(familyKey, "-", " ")))
        destRoot := this.GetUniqueDestinationPath(this.Config.ConsolidatedRoot, displayName)
        DirCreate(destRoot)

        ; Put current version front and center.
        if current.Type = "folder" {
            this.CopyFolderContents(current.Path, destRoot)
        } else {
            this.ExtractZip(current.Path, destRoot)
        }

        ; Older/source material goes to the back.
        archiveRoot := destRoot "\_archive_iterations"
        zipRoot := destRoot "\_source_zips"
        DirCreate(archiveRoot)
        DirCreate(zipRoot)

        for src in family {
            if src.Path = current.Path {
                if src.Type = "zip"
                    FileCopy(src.Path, this.GetUniqueDestinationPath(zipRoot, this.GetLeafName(src.Path)))
                continue
            }

            safeSource := this.SafeName(src.Name)
            if src.Type = "folder" {
                this.CopyFolderContents(src.Path, archiveRoot "\" safeSource)
            } else {
                FileCopy(src.Path, this.GetUniqueDestinationPath(zipRoot, this.GetLeafName(src.Path)))
                this.ExtractZip(src.Path, archiveRoot "\" safeSource)
            }
        }

        readme :=
            "CONSOLIDATED PROJECT - LOSSLESS COPY`r`n`r`n"
            . "Created: " FormatTime(, "yyyy-MM-dd HH:mm:ss") "`r`n"
            . "Family key: " familyKey "`r`n"
            . "Current/front source: " current.Path "`r`n`r`n"
            . "Root files are copied from the newest/current source.`r`n"
            . "_archive_iterations contains older extracted iterations.`r`n"
            . "_source_zips contains original ZIP files.`r`n"
            . "Original Desktop folders were not deleted.`r`n"

        FileAppend(readme, destRoot "\_README_CONSOLIDATION.txt", "UTF-8")
        return destRoot
    }

    ChooseCurrentSource(family) {
        best := family[1]
        for src in family {
            if src.Modified > best.Modified
                best := src
            else if src.Modified = best.Modified && src.PyCount > best.PyCount
                best := src
        }
        return best
    }

    CountPythonFiles(folder, maxDepth) {
        baseDepth := this.PathDepth(folder)
        count := 0

        Loop Files folder "\*", "FR" {
            if InStr(A_LoopFileAttrib, "D")
                continue

            currentDepth := this.PathDepth(A_LoopFileDir) - baseDepth
            if currentDepth > maxDepth
                continue

            if this.PathContainsExcludedFolder(A_LoopFileFullPath)
                continue

            ext := this.GetExtension(A_LoopFileFullPath)
            if ext = "py" || ext = "pyw"
                count += 1
        }

        return count
    }

    CountPythonFilesInZip(zipPath) {
        shell := ComObject("Shell.Application")
        zipFolder := shell.NameSpace(zipPath)
        if !zipFolder
            return 0
        return this.CountPythonInShellFolder(zipFolder)
    }

    CountPythonInShellFolder(shellFolder) {
        count := 0
        items := shellFolder.Items
        for item in items {
            name := item.Name
            if item.IsFolder {
                try count += this.CountPythonInShellFolder(item.GetFolder)
            } else {
                ext := StrLower(RegExReplace(name, "^.*\."))
                if ext = "py" || ext = "pyw"
                    count += 1
            }
        }
        return count
    }

    ExtractZip(zipPath, destDir) {
        DirCreate(destDir)
        ps :=
            "powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "
            . Chr(34)
            . "Expand-Archive -LiteralPath "
            . this.PSQuote(zipPath)
            . " -DestinationPath "
            . this.PSQuote(destDir)
            . " -Force"
            . Chr(34)
        RunWait(ps, , "Hide")
    }

    CopyFolderContents(srcDir, destDir) {
        DirCreate(destDir)
        cmd :=
            'robocopy "'
            . srcDir
            . '" "'
            . destDir
            . '" /E /COPY:DAT /DCOPY:DAT /R:1 /W:1 /NFL /NDL /NJH /NJS'
        RunWait(cmd, , "Hide")
    }

    WriteOrganizerReport(moved, leftovers) {
        path := this.Config.ReportsRoot "\desktop_file_organization_" FormatTime(, "yyyyMMdd_HHmmss") ".tsv"
        text := "Moved From`tMoved To`tCategory`r`n"
        for row in moved
            text .= row.From "`t" row.To "`t" row.Category "`r`n"
        text .= "`r`nLeftovers / Misc / Errors`r`n"
        for item in leftovers
            text .= item "`r`n"
        FileAppend(text, path, "UTF-8")
        this.LastReportPath := path
        return path
    }

    WriteProjectReport(sources, families, created, errors) {
        path := this.Config.ReportsRoot "\project_consolidation_" FormatTime(, "yyyyMMdd_HHmmss") ".tsv"
        text := "Project Sources`r`nPath`tType`tFamily`tPython Files`tModified`r`n"
        for src in sources
            text .= src.Path "`t" src.Type "`t" src.FamilyKey "`t" src.PyCount "`t" src.Modified "`r`n"

        text .= "`r`nCreated Consolidated Folders`r`n"
        for item in created
            text .= item "`r`n"

        text .= "`r`nErrors`r`n"
        for err in errors
            text .= err "`r`n"

        FileAppend(text, path, "UTF-8")
        this.LastReportPath := path
        return path
    }

    MoveItemPreservingName(sourcePath, destinationDirectory) {
        if !FileExist(sourcePath)
            return ""
        DirCreate(destinationDirectory)
        destinationPath := this.GetUniqueDestinationPath(destinationDirectory, this.GetLeafName(sourcePath))
        FileMove(sourcePath, destinationPath)
        return destinationPath
    }

    GetUniqueDestinationPath(destinationDirectory, leafName) {
        candidatePath := destinationDirectory "\" leafName
        if !FileExist(candidatePath) && !DirExist(candidatePath)
            return candidatePath

        SplitPath(leafName, , , &extension, &nameWithoutExtension)
        counter := 2
        Loop {
            if extension != ""
                candidateName := nameWithoutExtension " (" counter ")." extension
            else
                candidateName := leafName " (" counter ")"

            candidatePath := destinationDirectory "\" candidateName
            if !FileExist(candidatePath) && !DirExist(candidatePath)
                return candidatePath
            counter += 1
        }
    }

    ShouldSkipFolder(path) {
        name := this.GetLeafName(path)
        if this.Config.ExcludedFolderNames.Has(name)
            return true
        return false
    }

    PathContainsExcludedFolder(path) {
        parts := StrSplit(StrReplace(path, "/", "\"), "\")
        for part in parts {
            if this.Config.ExcludedFolderNames.Has(part)
                return true
        }
        return false
    }

    GetFamilyKey(name) {
        base := RegExReplace(name, "\.(zip|7z|rar)$", "")
        base := StrLower(base)
        base := RegExReplace(base, "[_\-.]+", " ")
        base := RegExReplace(base, "\([0-9]+\)", " ")
        base := RegExReplace(base, "\b(v?\d+(\.\d+){0,3}|\d{8})\b", " ")
        words := StrSplit(base, " ")
        cleaned := ""
        stopWords := Map(
            "fixed", true, "fix", true, "patched", true, "patch", true,
            "updated", true, "update", true, "final", true, "latest", true,
            "new", true, "complete", true, "full", true, "project", true,
            "copy", true, "backup", true, "old", true, "version", true,
            "iteration", true, "iter", true, "chatgpt", true, "gpt", true
        )

        for word in words {
            word := Trim(RegExReplace(word, "[^a-z0-9]", ""))
            if word = ""
                continue
            if stopWords.Has(word)
                continue
            cleaned .= (cleaned = "" ? "" : "-") word
        }

        if cleaned = ""
            cleaned := RegExReplace(StrLower(base), "[^a-z0-9]+", "-")

        return Trim(cleaned, "-")
    }

    GetNewestModifiedTime(folder) {
        newest := ""
        Loop Files folder "\*", "FR" {
            try t := FileGetTime(A_LoopFileFullPath, "M")
            catch
                continue
            if newest = "" || t > newest
                newest := t
        }
        return newest
    }

    PathDepth(path) {
        path := Trim(StrReplace(path, "/", "\"), "\")
        return StrSplit(path, "\").Length
    }

    OpenPath(path, *) {
        if FileExist(path) || DirExist(path)
            Run(path)
        else
            MsgBox("Path does not exist:`n" path, APP_TITLE, "Icon!")
    }

    PSQuote(text) {
        return "'" StrReplace(text, "'", "''") "'"
    }

    GetExtension(path) {
        SplitPath(path, , , &extension)
        return StrLower(extension)
    }

    GetLeafName(path) {
        SplitPath(path, &leafName)
        return leafName
    }

    SafeName(name) {
        name := RegExReplace(name, '[<>:"/\\|?*]', "_")
        name := Trim(name, " .")
        return name = "" ? "Unnamed" : name
    }

    TitleCase(text) {
        result := ""
        for word in StrSplit(text, " ") {
            if word = ""
                continue
            result .= (result = "" ? "" : " ") StrUpper(SubStr(word, 1, 1)) SubStr(word, 2)
        }
        return result
    }

    NormalizePath(path) {
        return StrLower(RTrim(StrReplace(path, "/", "\"), "\"))
    }

    PathsEqual(a, b) {
        return this.NormalizePath(a) = this.NormalizePath(b)
    }
}

global EvergreenApp := EvergreenDesktopOrganizer()

^!o::EvergreenApp.OrganizeLooseDesktopFiles(true)
^!c::EvergreenApp.ConsolidateProjects(true)
^!a::EvergreenApp.RunFullAutomation()
^!r::EvergreenApp.OpenPath(EvergreenApp.Config.ReportsRoot)
^!m::EvergreenApp.ShowActionMenu()
