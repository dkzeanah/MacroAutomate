#Requires AutoHotkey v2.0
#SingleInstance Force

; Standalone Everything 1.5 SDK v3 smoke test.
; It loads the same DLL used by the integrated workspace manager, connects to
; Everything, searches the index, and displays returned full paths.

class Everything3SDK {
    __New(dllPath) {
        this.DllPath := dllPath
        this.Module := 0
        this.Client := 0
        this.InstanceName := ""
        this.VersionText := ""
        this.LastError := ""
        this.LastConnectAttempt := 0
        this.ConnectRetryMs := 3000
        this.Procs := Map()

        this.Load()
    }

    Load() {
        if this.Module
            return true

        if !FileExist(this.DllPath) {
            this.LastError := "Everything3.dll was not found: " this.DllPath
            return false
        }

        this.Module := DllCall(
            "Kernel32\LoadLibraryW",
            "Str", this.DllPath,
            "Ptr"
        )
        if !this.Module {
            this.LastError := "LoadLibraryW failed for Everything3.dll. Win32 error: " A_LastError
            return false
        }

        requiredExports := [
            "Everything3_ConnectW",
            "Everything3_DestroyClient",
            "Everything3_CreateSearchState",
            "Everything3_DestroySearchState",
            "Everything3_SetSearchTextW",
            "Everything3_SetSearchViewportCount",
            "Everything3_Search",
            "Everything3_DestroyResultList",
            "Everything3_GetResultListViewportCount",
            "Everything3_GetResultFullPathNameW",
            "Everything3_IsFolderResult",
            "Everything3_GetLastError"
        ]

        for exportName in requiredExports {
            proc := DllCall(
                "Kernel32\GetProcAddress",
                "Ptr", this.Module,
                "AStr", exportName,
                "Ptr"
            )
            if !proc {
                this.LastError := "Everything3.dll is missing required export: " exportName
                this.UnloadModule()
                return false
            }
            this.Procs[exportName] := proc
        }

        ; A missing/running-later Everything process is not fatal. The wrapper
        ; remains loaded and EnsureConnected() will retry when a search is made.
        this.EnsureConnected(true)
        return true
    }

    EnsureConnected(force := false) {
        if this.Client
            return true

        if !this.Module
            return false

        if !force && this.LastConnectAttempt {
            elapsed := A_TickCount - this.LastConnectAttempt
            if (elapsed >= 0 && elapsed < this.ConnectRetryMs)
                return false
        }
        this.LastConnectAttempt := A_TickCount

        ; Current Everything 1.5 builds normally use the unnamed/default IPC
        ; instance. Older alpha builds commonly used the explicit 1.5a instance.
        client := DllCall(this.Procs["Everything3_ConnectW"], "Ptr", 0, "Ptr")
        instanceName := "default"

        if !client {
            client := DllCall(this.Procs["Everything3_ConnectW"], "Str", "1.5a", "Ptr")
            instanceName := "1.5a"
        }

        if !client {
            this.LastError := "Could not connect to Everything 1.5. Start Everything, then use Workspace actions -> Reconnect Everything3 SDK. SDK error: " this.GetLastErrorCodeText()
            return false
        }

        this.Client := client
        this.InstanceName := instanceName
        this.VersionText := this.ReadVersionText()
        this.LastError := ""
        return true
    }

    Reconnect() {
        this.DisconnectClient()
        this.LastConnectAttempt := 0
        return this.EnsureConnected(true)
    }

    Search(searchText, maxResults := 1000) {
        if (maxResults < 1)
            maxResults := 1

        if !this.EnsureConnected() {
            return {
                Ok: false,
                Results: [],
                ViewportCount: 0,
                Query: searchText,
                Error: this.LastError
            }
        }

        searchState := 0
        resultList := 0
        results := []

        try {
            searchState := DllCall(this.Procs["Everything3_CreateSearchState"], "Ptr")
            if !searchState
                throw Error("Everything3_CreateSearchState failed. SDK error: " this.GetLastErrorCodeText())

            if !DllCall(
                this.Procs["Everything3_SetSearchTextW"],
                "Ptr", searchState,
                "Str", searchText,
                "Int"
            )
                throw Error("Everything3_SetSearchTextW failed. SDK error: " this.GetLastErrorCodeText())

            ; Request one extra result. If it is returned, the GUI knows the
            ; configured display limit truncated the matching result set.
            requestedViewport := maxResults + 1
            if !DllCall(
                this.Procs["Everything3_SetSearchViewportCount"],
                "Ptr", searchState,
                "UPtr", requestedViewport,
                "Int"
            )
                throw Error("Everything3_SetSearchViewportCount failed. SDK error: " this.GetLastErrorCodeText())

            resultList := DllCall(
                this.Procs["Everything3_Search"],
                "Ptr", this.Client,
                "Ptr", searchState,
                "Ptr"
            )
            if !resultList
                throw Error("Everything3_Search failed. SDK error: " this.GetLastErrorCodeText())

            viewportCount := DllCall(
                this.Procs["Everything3_GetResultListViewportCount"],
                "Ptr", resultList,
                "UPtr"
            )

            Loop viewportCount {
                resultIndex := A_Index - 1

                ; SDK v3 returns the required UTF-16 character count (including
                ; the NUL) when bufsize is zero, so long paths are never clipped.
                requiredChars := DllCall(
                    this.Procs["Everything3_GetResultFullPathNameW"],
                    "Ptr", resultList,
                    "UPtr", resultIndex,
                    "Ptr", 0,
                    "UPtr", 0,
                    "UPtr"
                )
                if (requiredChars < 1)
                    continue

                pathBuffer := Buffer(requiredChars * 2, 0)
                copied := DllCall(
                    this.Procs["Everything3_GetResultFullPathNameW"],
                    "Ptr", resultList,
                    "UPtr", resultIndex,
                    "Ptr", pathBuffer.Ptr,
                    "UPtr", requiredChars,
                    "UPtr"
                )
                if !copied
                    continue

                fullPath := StrGet(pathBuffer.Ptr, "UTF-16")
                if (fullPath = "")
                    continue

                isFolder := DllCall(
                    this.Procs["Everything3_IsFolderResult"],
                    "Ptr", resultList,
                    "UPtr", resultIndex,
                    "Int"
                ) != 0

                results.Push({Path: fullPath, IsDirectory: isFolder})
            }

            this.LastError := ""
            return {
                Ok: true,
                Results: results,
                ViewportCount: viewportCount,
                Query: searchText,
                Error: ""
            }
        } catch as err {
            this.LastError := err.Message
            return {
                Ok: false,
                Results: [],
                ViewportCount: 0,
                Query: searchText,
                Error: err.Message
            }
        } finally {
            if resultList {
                try DllCall(
                    this.Procs["Everything3_DestroyResultList"],
                    "Ptr", resultList
                )
            }
            if searchState {
                try DllCall(
                    this.Procs["Everything3_DestroySearchState"],
                    "Ptr", searchState
                )
            }
        }
    }

    ReadVersionText() {
        names := [
            "Everything3_GetMajorVersion",
            "Everything3_GetMinorVersion",
            "Everything3_GetRevision",
            "Everything3_GetBuildNumber"
        ]
        values := []

        for exportName in names {
            proc := this.GetOptionalProc(exportName)
            if !proc
                return ""
            try values.Push(DllCall(proc, "Ptr", this.Client, "UInt"))
            catch
                return ""
        }

        return values[1] "." values[2] "." values[3] "." values[4]
    }

    GetOptionalProc(exportName) {
        if !this.Module
            return 0

        if this.Procs.Has(exportName)
            return this.Procs[exportName]

        proc := DllCall(
            "Kernel32\GetProcAddress",
            "Ptr", this.Module,
            "AStr", exportName,
            "Ptr"
        )
        if proc
            this.Procs[exportName] := proc
        return proc
    }

    GetLastErrorCodeText() {
        if !this.Module || !this.Procs.Has("Everything3_GetLastError")
            return "unavailable"

        try {
            code := DllCall(this.Procs["Everything3_GetLastError"], "UInt")
            return Format("{} (0x{:08X})", code, code)
        } catch {
            return "unavailable"
        }
    }

    DisconnectClient() {
        if this.Client {
            try DllCall(
                this.Procs["Everything3_DestroyClient"],
                "Ptr", this.Client
            )
            this.Client := 0
        }
        this.InstanceName := ""
        this.VersionText := ""
    }

    UnloadModule() {
        this.DisconnectClient()
        if this.Module {
            try DllCall("Kernel32\FreeLibrary", "Ptr", this.Module, "Int")
            this.Module := 0
        }
        this.Procs := Map()
    }

    Close() {
        this.UnloadModule()
    }

    __Delete() {
        this.Close()
    }
}

DllPath := "C:\Users\Don\Desktop\aAutomateMacro\lib\Everything3.dll"
Everything := Everything3SDK(DllPath)

if !Everything.EnsureConnected(true) {
    MsgBox(
        "Everything3 SDK connection failed.`n`n" Everything.LastError,
        "Everything3 SDK Test",
        "Icon!"
    )
    ExitApp()
}

; Change this to any normal Everything 1.5 search expression.
SearchText := "Everything3.dll"
Result := Everything.Search(SearchText, 50)
if !Result.Ok {
    MsgBox(
        "Search failed.`n`n" Result.Error,
        "Everything3 SDK Test",
        "Icon!"
    )
    ExitApp()
}

Output := "DLL: " DllPath "`n"
Output .= "Instance: " Everything.InstanceName "`n"
Output .= "Everything version: " (Everything.VersionText != "" ? Everything.VersionText : "unknown") "`n"
Output .= "Query: " SearchText "`n"
Output .= "Returned: " Result.Results.Length "`n`n"

for index, item in Result.Results {
    kind := item.IsDirectory ? "[DIR] " : "[FILE] "
    sizeText := ""
    if !item.IsDirectory {
        try sizeText := " | " FileGetSize(item.Path) " bytes"
    }
    Output .= index ". " kind item.Path sizeText "`n"
}

if (Result.Results.Length = 0)
    Output .= "No matching indexed items were returned.`n"

Output .= "`nSDK v3 note: Everything3_GetResultSize returns UInt64 directly;"
Output .= " it does not take the old SDK UInt64/LARGE_INTEGER output pointer."

MsgBox(Output, "Everything3 SDK Test")
Everything.Close()
ExitApp()
