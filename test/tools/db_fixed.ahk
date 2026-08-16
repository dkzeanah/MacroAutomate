;#Requires AutoHotkey v2.0
;#SingleInstance Force

SetWorkingDir(A_ScriptDir)
FileEncoding("UTF-8")

; ============================================================================
; CONFIGURATION
; ============================================================================

global SQLITE_EXE := A_ScriptDir "\sqlite3.exe"
global DB_FILE := A_ScriptDir "\ce_glossary.sqlite"

; This can be an exact file or a wildcard pattern.
; Examples:
;   A_ScriptDir "\CC-CEDICT.txt"
;   A_ScriptDir "\chinese_english\*.txt"
global SOURCE_PATTERN := A_ScriptDir "\CC-CEDICT.txt"

; Temporary files used to communicate with sqlite3.exe.
global BUILD_SQL_FILE := A_ScriptDir "\ce_glossary_build.sql"
global QUERY_SQL_FILE := A_ScriptDir "\ce_glossary_query.sql"
global SQLITE_STDOUT_FILE := A_ScriptDir "\sqlite_stdout.txt"
global SQLITE_STDERR_FILE := A_ScriptDir "\sqlite_stderr.txt"
global SQLITE_RUNNER_FILE := A_ScriptDir "\run_sqlite_temp.cmd"
global SQLITE_LOG_FILE := A_ScriptDir "\sqlite_log.txt"

OnExit(CleanUpTemporaryFiles)

; ============================================================================
; MAIN
; ============================================================================

try
{
    ValidateRequirements()

    stats := BuildDatabase()
    insertedCount := ExecuteScalar("SELECT COUNT(*) FROM glossary;")

    MsgBox(
        insertedCount " unique row(s) inserted.`n"
        stats.Parsed " valid source row(s) parsed.`n"
        stats.Skipped " blank, comment, or invalid row(s) skipped.`n"
        stats.Files " source file(s) processed.",
        "CC-CEDICT Import Complete",
        "Iconi"
    )

    searchBox := InputBox(
        "Enter Chinese or English text to search for:",
        "Search CC-CEDICT",
        "w520 h150",
        "職業"
    )

    if (searchBox.Result != "OK")
        ExitApp()

    searchText := Trim(searchBox.Value)

    if (searchText = "")
    {
        MsgBox("No search text was entered.", "Search Cancelled", "Icon!")
        ExitApp()
    }

    ShowSearchResults(searchText)
}
catch as err
{
    errorText := err.Message

    if (err.Extra != "")
        errorText .= "`n`n" err.Extra

    AppendPersistentLog(errorText)

    MsgBox(
        "The glossary build failed.`n`n" errorText
        "`n`nA detailed copy was written to:`n" SQLITE_LOG_FILE,
        "db.ahk Error",
        "Iconx"
    )

    ExitApp()
}

; ============================================================================
; DATABASE BUILD
; ============================================================================

BuildDatabase()
{
    global SOURCE_PATTERN
    global BUILD_SQL_FILE

    parsedCount := 0
    skippedCount := 0
    fileCount := 0

    SafeDelete(BUILD_SQL_FILE)

    writer := FileOpen(BUILD_SQL_FILE, "w", "UTF-8-RAW")

    if !IsObject(writer)
        throw Error("Could not create the SQL build file.",, BUILD_SQL_FILE)

    try
    {
        ; The table is rebuilt on every run so repeated execution does not
        ; continually append duplicate rows.
        writer.Write(
            "PRAGMA encoding = 'UTF-8';`n"
            "PRAGMA synchronous = NORMAL;`n"
            "PRAGMA temp_store = MEMORY;`n"
            "CREATE TABLE IF NOT EXISTS glossary (`n"
            "    id INTEGER PRIMARY KEY,`n"
            "    chinese TEXT NOT NULL,`n"
            "    english TEXT NOT NULL`n"
            ");`n"
            "BEGIN IMMEDIATE;`n"
            "DELETE FROM glossary;`n"
            "DROP INDEX IF EXISTS ux_glossary_chinese_english;`n"
            "CREATE UNIQUE INDEX ux_glossary_chinese_english`n"
            "ON glossary(chinese, english);`n"
        )

        Loop Files, SOURCE_PATTERN, "F"
        {
            fileCount++

            Loop Read, A_LoopFileFullPath
            {
                chinese := ""
                english := ""

                if ParseSourceLine(A_LoopReadLine, &chinese, &english)
                {
                    writer.Write(
                        "INSERT OR IGNORE INTO glossary (chinese, english) VALUES ("
                        SqlQuote(chinese) ", " SqlQuote(english) ");`n"
                    )

                    parsedCount++
                }
                else
                {
                    skippedCount++
                }
            }
        }

        writer.Write("COMMIT;`n")
    }
    finally
    {
        writer.Close()
    }

    if (fileCount = 0)
    {
        throw Error(
            "No CC-CEDICT source files matched SOURCE_PATTERN.",
            ,
            SOURCE_PATTERN
        )
    }

    ExecuteSqlFile(BUILD_SQL_FILE)

    return {
        Parsed: parsedCount,
        Skipped: skippedCount,
        Files: fileCount
    }
}

ParseSourceLine(sourceLine, &chinese, &english)
{
    chinese := ""
    english := ""

    ; Remove a possible UTF-8 BOM and surrounding whitespace.
    line := StrReplace(sourceLine, Chr(0xFEFF), "")
    line := Trim(line, " `t`r`n")

    ; CC-CEDICT metadata and copyright lines begin with #.
    if (line = "" || SubStr(line, 1, 1) = "#")
        return false

    ; ------------------------------------------------------------------------
    ; FORMAT 1: Tab-separated excerpt
    ;
    ; Chinese<TAB>English
    ; ------------------------------------------------------------------------

    tabPosition := InStr(line, "`t")

    if tabPosition
    {
        chinese := Trim(SubStr(line, 1, tabPosition - 1))
        english := Trim(SubStr(line, tabPosition + 1))

        ; Prevent embedded tabs from breaking SQLite tab-mode query output.
        english := StrReplace(english, "`t", " ")

        return (chinese != "" && english != "")
    }

    ; ------------------------------------------------------------------------
    ; FORMAT 2: Official CC-CEDICT export
    ;
    ; Traditional Simplified [pin1 yin1] /definition one/definition two/
    ; ------------------------------------------------------------------------

    if RegExMatch(
        line,
        "^(\S+)\s+(\S+)\s+\[([^\]]*)\]\s+/(.*)/\s*$",
        &match
    )
    {
        traditional := Trim(match[1])
        simplified := Trim(match[2])
        pinyin := Trim(match[3])
        definitions := Trim(match[4])

        definitions := StrReplace(definitions, "/", "; ")

        if (traditional = simplified)
            chinese := simplified
        else
            chinese := traditional " / " simplified

        if (pinyin != "")
            english := "[" pinyin "] " definitions
        else
            english := definitions

        return (chinese != "" && english != "")
    }

    ; Any line that is neither valid TSV nor valid official CC-CEDICT syntax
    ; is deliberately skipped instead of being placed into an SQL statement.
    return false
}

; ============================================================================
; SQL EXECUTION
; ============================================================================

ExecuteSqlFile(sqlFile)
{
    global SQLITE_EXE
    global DB_FILE
    global SQLITE_STDOUT_FILE
    global SQLITE_STDERR_FILE
    global SQLITE_RUNNER_FILE

    SafeDelete(SQLITE_STDOUT_FILE)
    SafeDelete(SQLITE_STDERR_FILE)
    SafeDelete(SQLITE_RUNNER_FILE)

    batchText := "@echo off`r`n"
    batchText .= "chcp 65001 >nul`r`n"
    batchText .= QuoteCommandArgument(SQLITE_EXE)
    batchText .= " -batch -bail "
    batchText .= QuoteCommandArgument(DB_FILE)
    batchText .= " < " QuoteCommandArgument(sqlFile)
    batchText .= " > " QuoteCommandArgument(SQLITE_STDOUT_FILE)
    batchText .= " 2> " QuoteCommandArgument(SQLITE_STDERR_FILE) "`r`n"
    batchText .= "exit /b %errorlevel%`r`n"

    FileAppend(batchText, SQLITE_RUNNER_FILE, "UTF-8-RAW")

    command := Format(
        '"{1}" /D /C call "{2}"',
        A_ComSpec,
        SQLITE_RUNNER_FILE
    )

    exitCode := RunWait(command, A_ScriptDir, "Hide")

    stdoutText := ""
    stderrText := ""

    if FileExist(SQLITE_STDOUT_FILE)
        stdoutText := FileRead(SQLITE_STDOUT_FILE, "UTF-8-RAW")

    if FileExist(SQLITE_STDERR_FILE)
        stderrText := FileRead(SQLITE_STDERR_FILE, "UTF-8-RAW")

    if (exitCode != 0 || Trim(stderrText) != "")
    {
        extraText := "Exit code: " exitCode
        extraText .= "`nSQL file: " sqlFile

        if (Trim(stderrText) != "")
            extraText .= "`n`nsqlite3.exe output:`n" stderrText

        throw Error("sqlite3.exe reported an error.",, extraText)
    }

    return stdoutText
}

ExecuteSqlText(sqlText)
{
    global QUERY_SQL_FILE

    SafeDelete(QUERY_SQL_FILE)

    writer := FileOpen(QUERY_SQL_FILE, "w", "UTF-8-RAW")

    if !IsObject(writer)
        throw Error("Could not create the SQL query file.",, QUERY_SQL_FILE)

    try
    {
        writer.Write(sqlText)
    }
    finally
    {
        writer.Close()
    }

    return ExecuteSqlFile(QUERY_SQL_FILE)
}

ExecuteScalar(sqlStatement)
{
    sqlText := ".headers off`n"
    sqlText .= ".mode list`n"
    sqlText .= sqlStatement

    if (SubStr(Trim(sqlText), -1) != ";")
        sqlText .= ";"

    sqlText .= "`n"

    return Trim(ExecuteSqlText(sqlText))
}

SearchDatabase(searchText)
{
    likeValue := SqlQuote("%" searchText "%")

    sqlText := ".headers off`n"
    sqlText .= ".mode tabs`n"
    sqlText .= "SELECT chinese, english`n"
    sqlText .= "FROM glossary`n"
    sqlText .= "WHERE chinese LIKE " likeValue "`n"
    sqlText .= "   OR english LIKE " likeValue "`n"
    sqlText .= "ORDER BY chinese`n"
    sqlText .= "LIMIT 100;`n"

    return ExecuteSqlText(sqlText)
}

SqlQuote(value)
{
    ; SQL text literals use single quotes. Any single quote contained in the
    ; source text must be doubled. Double quotes do not need special handling.
    value := StrReplace(value, Chr(0), "")
    value := StrReplace(value, "`r", " ")
    value := StrReplace(value, "`n", " ")
    value := StrReplace(value, "'", "''")

    return "'" value "'"
}

QuoteCommandArgument(value)
{
    ; Windows filenames cannot contain a literal double quote, so wrapping the
    ; complete path is sufficient and correctly handles spaces.
    return '"' value '"'
}

; ============================================================================
; SEARCH RESULT DISPLAY
; ============================================================================

ShowSearchResults(searchText)
{
    rawResults := SearchDatabase(searchText)

    if (Trim(rawResults) = "")
    {
        MsgBox(
            "No matches were found for:`n`n" searchText,
            "CC-CEDICT Search",
            "Iconi"
        )
        return
    }

    resultCount := 0
    displayText := ""

    Loop Parse, rawResults, "`n", "`r"
    {
        rowText := A_LoopField

        if (rowText = "")
            continue

        fields := StrSplit(rowText, "`t",, 2)

        chinese := fields[1]
        english := fields.Length >= 2 ? fields[2] : ""

        resultCount++
        displayText .= resultCount ". " chinese "`n"
        displayText .= "    " english "`n`n"
    }

    MsgBox(
        resultCount " result(s) for: " searchText "`n`n" displayText,
        "CC-CEDICT Search Results",
        "Iconi"
    )
}

; ============================================================================
; VALIDATION, LOGGING, AND CLEANUP
; ============================================================================

ValidateRequirements()
{
    global SQLITE_EXE
    global SOURCE_PATTERN

    if !FileExist(SQLITE_EXE)
    {
        throw Error(
            "sqlite3.exe was not found next to this script.",
            ,
            SQLITE_EXE
        )
    }

    foundSource := false

    Loop Files, SOURCE_PATTERN, "F"
    {
        foundSource := true
        break
    }

    if !foundSource
    {
        throw Error(
            "The CC-CEDICT source file was not found.",
            ,
            SOURCE_PATTERN
        )
    }
}

AppendPersistentLog(text)
{
    global SQLITE_LOG_FILE

    timestamp := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")

    FileAppend(
        "`r`n============================================================`r`n"
        timestamp "`r`n"
        text "`r`n",
        SQLITE_LOG_FILE,
        "UTF-8-RAW"
    )
}

CleanUpTemporaryFiles(*)
{
    global BUILD_SQL_FILE
    global QUERY_SQL_FILE
    global SQLITE_STDOUT_FILE
    global SQLITE_STDERR_FILE
    global SQLITE_RUNNER_FILE

    SafeDelete(BUILD_SQL_FILE)
    SafeDelete(QUERY_SQL_FILE)
    SafeDelete(SQLITE_STDOUT_FILE)
    SafeDelete(SQLITE_STDERR_FILE)
    SafeDelete(SQLITE_RUNNER_FILE)
}

SafeDelete(path)
{
    if !FileExist(path)
        return

    try
    {
        FileDelete(path)
    }
    catch
    {
        ; Cleanup failures are intentionally non-fatal.
    }
}
