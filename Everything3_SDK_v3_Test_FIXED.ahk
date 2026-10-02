#Requires AutoHotkey v2.0
#SingleInstance Force

; Standalone Everything 1.5 SDK v3 smoke test.
; It loads the same DLL used by the integrated workspace manager, connects to
; Everything, searches the index, and displays returned full paths.

class Everything3SDK {
    __New(dllPath) {
        this.DllPath := dllPath
        this.DllVersion := ""
        this.Module := 0
        this.Client := 0
        this.InstanceName := ""
        this.VersionText := ""
        this.LastError := ""
        this.LastViewportDiagnostic := "Not tested yet."
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

        ; SDK 3.0.0.4+ includes Windows file-version metadata. Older DLLs may
        ; legitimately return a blank version string here.
        try this.DllVersion := FileGetVersion(this.DllPath)
        catch
            this.DllVersion := ""

        this.Module := DllCall(
            "Kernel32\LoadLibraryW",
            "Str", this.DllPath,
            "Ptr"
        )
        if !this.Module {
            this.LastError := "LoadLibraryW failed for Everything3.dll. Win32 error: " A_LastError
            return false
        }

        ; Viewport functions are intentionally NOT required. Some older SDK3
        ; DLL builds return FALSE from SetSearchViewportCount while still
        ; changing the search state. Search() probes this behavior and falls
        ; back to Everything's count:<n> syntax if necessary.
        requiredExports := [
            "Everything3_ConnectW",
            "Everything3_DestroyClient",
            "Everything3_CreateSearchState",
            "Everything3_DestroySearchState",
            "Everything3_SetSearchTextW",
            "Everything3_Search",
            "Everything3_DestroyResultList",
            "Everything3_GetResultListViewportCount",
            "Everything3_GetResultFullPathNameW",
            "Everything3_IsFolderResult"
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
        defaultError := A_LastError
        instanceName := "default"

        if !client {
            client := DllCall(this.Procs["Everything3_ConnectW"], "Str", "1.5a", "Ptr")
            alphaError := A_LastError
            instanceName := "1.5a"
        } else {
            alphaError := 0
        }

        if !client {
            this.LastError := (
                "Could not connect to Everything 1.5. Start Everything and make sure "
                "the Everything 1.5 IPC server is enabled.`n"
                "Unnamed instance error: " this.FormatErrorCode(defaultError) "`n"
                "1.5a instance error: " this.FormatErrorCode(alphaError)
            )
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
                OriginalQuery: searchText,
                Error: this.LastError
            }
        }

        searchState := 0
        resultList := 0
        results := []

        try {
            searchState := DllCall(this.Procs["Everything3_CreateSearchState"], "Ptr")
            createError := A_LastError
            if !searchState
                throw Error("Everything3_CreateSearchState failed. SDK/Win32 error: " this.FormatErrorCode(createError))

            ; Ask for one extra row so the caller can tell that its display cap
            ; truncated the result set.
            requestedViewport := maxResults + 1
            effectiveQuery := searchText
            viewportConfirmed := false
            viewportSetter := this.GetOptionalProc("Everything3_SetSearchViewportCount")
            viewportGetter := this.GetOptionalProc("Everything3_GetSearchViewportCount")

            if viewportSetter {
                ; Clear the thread last-error value before the call so a FALSE +
                ; error 0 result is unambiguous.
                DllCall("Kernel32\SetLastError", "UInt", 0)
                setResult := DllCall(
                    viewportSetter,
                    "Ptr", searchState,
                    "UPtr", requestedViewport,
                    "Int"
                )
                setError := A_LastError

                if setResult {
                    viewportConfirmed := true
                    this.LastViewportDiagnostic := (
                        "SetSearchViewportCount returned TRUE for " requestedViewport "."
                    )
                } else if viewportGetter {
                    actualViewport := DllCall(
                        viewportGetter,
                        "Ptr", searchState,
                        "UPtr"
                    )
                    getError := A_LastError

                    if (actualViewport = requestedViewport) {
                        ; This is the exact case shown by the user's screenshot:
                        ; FALSE with error 0, but the state may still have changed.
                        ; Treat the getter as authoritative instead of aborting.
                        viewportConfirmed := true
                        this.LastViewportDiagnostic := (
                            "SetSearchViewportCount returned FALSE, but GetSearchViewportCount "
                            "confirmed " actualViewport ". Setter error: "
                            this.FormatErrorCode(setError) ". Treated as success."
                        )
                    } else {
                        this.LastViewportDiagnostic := (
                            "Viewport setter was not usable. Requested " requestedViewport
                            ", getter returned " actualViewport ". Setter error: "
                            this.FormatErrorCode(setError) ", getter error: "
                            this.FormatErrorCode(getError) ". Using count:<n> fallback."
                        )
                    }
                } else {
                    this.LastViewportDiagnostic := (
                        "SetSearchViewportCount returned FALSE ("
                        this.FormatErrorCode(setError)
                        ") and GetSearchViewportCount is unavailable. Using count:<n> fallback."
                    )
                }
            } else {
                this.LastViewportDiagnostic := (
                    "Viewport setter export is unavailable. Using count:<n> fallback."
                )
            }

            ; count:<n> is an official Everything search function. It is a safe
            ; compatibility fallback for older/broken SDK3 viewport setters and
            ; also prevents an unnecessarily large search from being processed.
            if !viewportConfirmed
                effectiveQuery := "count:" requestedViewport " " searchText

            DllCall("Kernel32\SetLastError", "UInt", 0)
            setTextResult := DllCall(
                this.Procs["Everything3_SetSearchTextW"],
                "Ptr", searchState,
                "Str", effectiveQuery,
                "Int"
            )
            setTextError := A_LastError
            if !setTextResult
                throw Error("Everything3_SetSearchTextW failed. SDK/Win32 error: " this.FormatErrorCode(setTextError))

            DllCall("Kernel32\SetLastError", "UInt", 0)
            resultList := DllCall(
                this.Procs["Everything3_Search"],
                "Ptr", this.Client,
                "Ptr", searchState,
                "Ptr"
            )
            searchError := A_LastError
            if !resultList
                throw Error("Everything3_Search failed. SDK/Win32 error: " this.FormatErrorCode(searchError))

            viewportCount := DllCall(
                this.Procs["Everything3_GetResultListViewportCount"],
                "Ptr", resultList,
                "UPtr"
            )

            ; Never enumerate more than the number we explicitly asked for,
            ; even if an old DLL reports an unexpectedly large viewport.
            enumerateCount := Min(viewportCount, requestedViewport)

            Loop enumerateCount {
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
                Query: effectiveQuery,
                OriginalQuery: searchText,
                Error: ""
            }
        } catch as err {
            this.LastError := err.Message
            return {
                Ok: false,
                Results: [],
                ViewportCount: 0,
                Query: searchText,
                OriginalQuery: searchText,
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

    FormatErrorCode(code) {
        ; Everything3_GetLastError is a wrapper around Windows GetLastError.
        ; AutoHotkey captures that value in A_LastError immediately after each
        ; DllCall, so pass the captured value here instead of making another
        ; DllCall that could overwrite the thread's last-error state.
        return Format("{} (0x{:08X})", code, code & 0xFFFFFFFF)
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
Output .= "SDK DLL version: " (Everything.DllVersion != "" ? Everything.DllVersion : "unknown/pre-3.0.0.4") "`n"
Output .= "Instance: " Everything.InstanceName "`n"
Output .= "Everything version: " (Everything.VersionText != "" ? Everything.VersionText : "unknown") "`n"
Output .= "Original query: " SearchText "`n"
Output .= "Effective query: " Result.Query "`n"
Output .= "Viewport diagnostic: " Everything.LastViewportDiagnostic "`n"
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
