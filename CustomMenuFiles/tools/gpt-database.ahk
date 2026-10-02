#singleInstance force

; Global variables
global SQLCommands, DB

; Main entry point
SQLCommands := ReadCommandsFromFile()
DB := SqliteDB()

InitializeGUI()


ReadCommandsFromFile() {
    SQLCommandsFile := "sql_commands.txt"
    SQLCommands := []
    if FileExist(SQLCommandsFile) {
        SQLCommandsText := FileRead(SQLCommandsFile)
        for cmd in StrSplit(SQLCommandsText, "`n", "`r") {
            cmd := Trim(cmd)
            if (cmd != "")
                SQLCommands.Push(cmd)
        }
    } else {
        ; Initial commands provided at the beginning
        SQLCommandsText := "
        (LTrim Join`r`n
        INSERT INTO AnswerContacts (AnswerID, ContactID) VALUES (?, ?);
        INSERT INTO AnswerMaterials (AnswerID, MaterialID) VALUES (?, ?);
        INSERT INTO AnswerTools (AnswerID, ToolID) VALUES (?, ?);
        INSERT INTO Answers (QuestionID, AnswerText) VALUES (?, ?);
        INSERT INTO CarDetailsTable (CarID, TAG, FINAS, VINLAST4, HARNESS_STATUS, FullVIN) VALUES (?, ?, ?, ?, ?, ?);
        INSERT INTO ChatLog (Prompt, Response, ReferenceNumber) VALUES (?, ?, ?);
        INSERT INTO CodeBlock (Language, Code) VALUES (?, ?);
        INSERT INTO Contacts (ContactName, ContactField) VALUES (?, ?);
        INSERT INTO ErrorLogTable (CarID, ErrorDetails, ErrorPriority, ErrorNotes) VALUES (?, ?, ?, ?);
        INSERT INTO EventTable (CarID, UserID, EventTypeID, StartTime, EndTime) VALUES (?, ?, ?, ?, ?);
        INSERT INTO Experts (ExpertName, ExpertField) VALUES (?, ?);
        INSERT INTO LogTable (TableName, Action) VALUES (?, ?);
        INSERT INTO LoggerTable (CarID, TypeLogger, NumLoggers) VALUES (?, ?, ?);
        INSERT INTO Materials (MaterialName, MaterialType) VALUES (?, ?);
        INSERT INTO QuestionContacts (QuestionID, ContactID) VALUES (?, ?);
        INSERT INTO QuestionMaterials (QuestionID, MaterialID) VALUES (?, ?);
        INSERT INTO QuestionTools (QuestionID, ToolID) VALUES (?, ?);
        INSERT INTO Questions (SubjectID, QuestionText) VALUES (?, ?);
        INSERT INTO RepairTable (CarID, TechnicianID, RepairDetails, RepairStart, RepairEnd) VALUES (?, ?, ?, ?, ?);
        INSERT INTO Resources (SubjectID, ResourceType, ResourceText) VALUES (?, ?, ?);
        INSERT INTO SoftwareTable (CarID, HeadUnit, SoftwareVersion, NextSoftwareVersion) VALUES (?, ?, ?, ?);
        INSERT INTO SubjectContacts (SubjectID, ContactID) VALUES (?, ?);
        INSERT INTO SubjectMaterials (SubjectID, MaterialID) VALUES (?, ?);
        INSERT INTO SubjectTools (SubjectID, ToolID) VALUES (?, ?);
        INSERT INTO Subjects (SubjectName, SubjectDescription) VALUES (?, ?);
        INSERT INTO Test (Name, Fname, Phone, Room) VALUES (?, ?, ?, ?);
        INSERT INTO Tools (ToolName, ToolDescription) VALUES (?, ?);
        INSERT INTO Users (UserName, Email) VALUES (?, ?);
        )"
        FileAppend(SQLCommandsText, SQLCommandsFile)
        ; Read the commands again
        SQLCommandsText := FileRead(SQLCommandsFile)
        for cmd in StrSplit(SQLCommandsText, "`n", "`r") {
            cmd := Trim(cmd)
            if (cmd != "")
                SQLCommands.Push(cmd)
        }
    }
    return SQLCommands
}

InitializeGUI() {
    global SQLCommands, ParamControls, Gui1

    ; Create the GUI object
    Gui1 := Gui("+Resize", "SQL Command Executor")
    Gui1.SetFont("s10", "Segoe UI")

    ; Add GUI elements
    Gui1.AddText("", "Select SQL Command:")
    CB := Gui1.AddComboBox("w600 vSQLCommand", SQLCommands)
    CB.OnEvent("Change", OnCommandSelected)

    CommandText := Gui1.AddEdit("ReadOnly w600 h50 vCommandText")

    Gui1.AddText("xm", "Enter parameters:")


    ; Create parameter labels and edits, hidden by default
    ParamControls := []
    Loop 10 {
        ParamLabel := Gui1.AddText("vParamLabel" A_Index, "Parameter " A_Index ":")
        ParamEdit := Gui1.AddEdit("w200 vParam" A_Index)
        ParamControls.Push({Label: ParamLabel, Edit: ParamEdit})
    }

    ExecuteButton := Gui1.AddButton("Default", "Execute")
    ExecuteButton.OnEvent("Click", ExecuteSQL)

    SaveButton := Gui1.AddButton("", "Save Command to List")
    SaveButton.OnEvent("Click", SaveCommand)

    Gui1.Show()
}

;; Event handler when a command is selected
OnCommandSelected(ctrl, info) {
    global Gui1, ParamControls

    SelectedCommand := ctrl.Value
    ; Display the selected command in the CommandText edit control
   ; Gui1.Submit("NoHide")
   ; Gui1.ControlSetText("CommandText", SelectedCommand)
   gui1["CommandText"].Value := SelectedCommand


    ; Parse the command to count the number of parameters '?'
    TempCommand := SelectedCommand
    ParamCount := 0
    while (pos := InStr(TempCommand, "?")) {
        ParamCount += 1
        TempCommand := SubStr(TempCommand, pos + 1)
    }

    ; Hide all parameter inputs first
    for i, pc in ParamControls {
		  pc.Label.Visible := false
        pc.Edit.Visible := false
        pc.Edit.Value := ""  ; Clear previous values
        ;pc.Label.Hide()
        ;pc.Edit.Hide()
       ; pc.Edit.Value := ""  ; Clear previous values
    }

    ; Show the needed parameter inputs
    for i, pc in ParamControls {
        if (i <= ParamCount) {
            pc.Label.Show()
            pc.Edit.Show()
        } else {
            break
        }
    }
}
; Function to execute the SQL command
ExecuteSQL(btn, info) {
    global Gui1, DB, ParamControls
    ;global Gui1, ParamControls

    Gui1.Submit("NoHide")

    Gui1.ControlGetText(&SelectedCommand, "SQLCommand")
    ; Get the parameter values
    ParamValues := []
    for i, pc in ParamControls {
        if pc.Edit.Visible {
            ParamValue := pc.Edit.Value
            ParamValues.Push(ParamValue)
        }
    }

	;DBFileName := A_ScriptDir . "C:\dev\Car.sqlite"cc
    ;DBFileName := CustomMenuPath "\logs\test.sqlite"
    ; Initialize the database connection
    if (!IsObject(DB)) {
        DB := SQLiteDB()
        if (!DB.OpenDB("kb.db")) {
            MsgBox("Error opening database: " . DB.ErrorMsg, "Database Error", 16)
            return
        }
    }

    ; Prepare the statement
    if (!DB.Prepare(SelectedCommand, ST)) {
        MsgBox("Error: " . DB.ErrorMsg, "SQL Error", 16)
        return
    }

    ; Bind the parameters
    Params := {}
    for i, val in ParamValues {
        Params[i] := {Text: val}
    }
    if (!ST.Bind(Params)) {
        MsgBox("Error: " . ST.ErrorMsg, "SQL Error", 16)
        ST.Free()
        return
    }

    ; Step the statement
    Result := ST.Step()
    if (Result == -1 || Result == True) {
        ; Command executed successfully
        MsgBox("SQL command executed successfully.", "Success", 64)
    } else {
        MsgBox("Error executing command: " . ST.ErrorMsg, "SQL Error", 16)
    }

    ; Finalize the statement
    ST.Free()
}

; Function to save a custom command to the list
SaveCommand(btn, info) {
    global Gui1, SQLCommands

    Gui1.ControlGetText(&SelectedCommand, "SQLCommand")
    ; Check if the command is already in the list
    ;if !(SelectedCommand in SQLCommands) {
        ; Add to the list
        SQLCommands.Push(SelectedCommand)
        ; Save to the file
        FileAppend("`n" SelectedCommand, "sql_commands.txt")
        ; Update the ComboBox
        Gui1.Control("Choose1||" . SQLCommands.Join("`n"), "SQLCommand")
        MsgBox("Command saved to the list.", "Success", 64)
   ; } else {
    ;    MsgBox("Command is already in the list.", "Info", 64)
   ; }
}


Class SQLiteDB {

      Static Version := ""
   Static _SQLiteDLL := "C:\Users\don\Desktop\SQLite3.dll"
   Static _RefCount := 0
   Static _MinVersion := "3.6"

   ; CONSTRUCTOR __New
   __New() {
      Local DLL, LibVersion, SQLiteDLL
      This._Path := ""                  ; Database path                                 (String)
      This._Handle := 0                 ; Database handle                               (Pointer)
      This._Stmts := Map()              ; Valid prepared statements                     (Map)
      If (SQLiteDB._RefCount = 0) {
         SQLiteDLL := SQLiteDB._SQLiteDLL
         If !FileExist(SQLiteDLL)
            If FileExist(A_ScriptDir . "\SQLiteDB.ini") {
               SQLiteDLL := IniRead(A_ScriptDir . "\SQLiteDB.ini", "Main", "DllPath", SQLiteDLL)
               SQLiteDB._SQLiteDLL := SQLiteDLL
         }
         If !(DLL := DllCall("LoadLibrary", "Str", SQLiteDB._SQLiteDLL, "UPtr")) {
            MsgBox("DLL " . SQLiteDLL . " does not exist!", "SQLiteDB Error", 16)
            ExitApp
         }
         LibVersion := StrGet(DllCall("SQlite3.dll\sqlite3_libversion", "Cdecl UPtr"), "UTF-8")
         If (VerCompare(LibVersion, SQLiteDB._MinVersion) < 0) {
            DllCall("FreeLibrary", "Ptr", DLL)
            MsgBox("Version " . LibVersion . " of SQLite3.dll is not supported!`n`n" .
                   "You can download the current version from www.sqlite.org!",
                   "SQLiteDB ERROR", 16)
            ExitApp
         }
         SQLiteDB.Version := LibVersion
      }
      SQLiteDB._RefCount += 1
   }

   __Delete() {
      Local DLL
      If (This._Handle)
         This.CloseDB()
      SQLiteDB._RefCount -= 1
      If (SQLiteDB._RefCount = 0) {
         If (DLL := DllCall("GetModuleHandle", "Str", SQLiteDB._SQLiteDLL, "UPtr"))
            DllCall("FreeLibrary", "Ptr", DLL)
      }
   }

    ErrorMsg := ""              ; Error message                           (String)
    ErrorCode := 0              ; SQLite error code / ErrorLevel          (Variant)
    Changes := 0                ; Changes made by last call of Exec()     (Integer)
    SQL := ""                   ; Last executed SQL statement             (String)

   OpenDB(DBPath, Access := "W", Create := True) {
      Static SQLITE_OPEN_READONLY  := 0x01 ; Database opened as read-only
      Static SQLITE_OPEN_READWRITE := 0x02 ; Database opened as read-write
      Static SQLITE_OPEN_CREATE    := 0x04 ; Database will be created if not exists
      Static MEMDB := ":memory:"
      Local Flags, HDB, RC, UTF8
      This.ErrorMsg := ""
      This.ErrorCode := 0
      HDB := 0
      If (DBPath = "")
         DBPath := MEMDB
      If (DBPath = This._Path) && (This._Handle)
         Return True
      If (This._Handle)
         Return This._SetError(0, "you must first close DB`n" . This._Path)
      Flags := 0
      Access := SubStr(Access, 1, 1)
      If (Access != "W") && (Access != "R")
         Access := "R"
      Flags := SQLITE_OPEN_READONLY
      If (Access = "W") {
         Flags := SQLITE_OPEN_READWRITE
         If (Create)
            Flags |= SQLITE_OPEN_CREATE
      }
      This._Path := DBPath
      UTF8 := This._StrToUTF8(DBPath)
      HDB := 0
      RC := DllCall("SQlite3.dll\sqlite3_open_v2", "Ptr", UTF8, "UPtrP", &HDB, "Int", Flags, "Ptr", 0, "Cdecl Int")
      If (RC) {
         This._Path := ""
         Return This._SetError(RC, This._ErrStr(RC) . "`n" . DBPath)
      }
      This._Handle := HDB
      Return True
   }

   CloseDB() {
      Local Each, Stmt, RC
      This.ErrorMsg := ""
      This.ErrorCode := 0
      This.SQL := ""
      If !(This._Handle)
         Return True
      For Each, Stmt in This._Stmts
         DllCall("SQlite3.dll\sqlite3_finalize", "Ptr", Stmt, "Cdecl Int")
      If (RC := DllCall("SQlite3.dll\sqlite3_close", "Ptr", This._Handle, "Cdecl Int"))
         Return This._SetError(RC)
      This._Path := ""
      This._Handle := ""
      This._Stmts := Map()
      Return True
   }

   AttachDB(DBPath, DBAlias) {
      Return This.Exec("ATTACH DATABASE '" . DBPath . "' As " . DBAlias . ";")
   }

   DetachDB(DBAlias) {
      Return This.Exec("DETACH DATABASE " . DBAlias . ";")
   }

   Exec(SQL, Callback := "") {
      Local CBPtr, Err, RC, UTF8
      This.ErrorMsg := ""
      This.ErrorCode := 0
      This.SQL := SQL
      If !(This._Handle)
         Return This._SetError(0, "Invalid database handle!")
      CBPtr := 0
      Err := 0
      If (Type(Callback) = "Func") && (Callback.MinParams = 4)
         CBPtr := CallbackCreate(Callback, "C", 4)
      UTF8 := This._StrToUTF8(SQL)
      RC := DllCall("SQlite3.dll\sqlite3_exec", "Ptr", This._Handle, "Ptr", UTF8, "Int", CBPtr, "Ptr", ObjPtr(This),
                    "UPtrP", &Err, "Cdecl Int")
      If (CBPtr)
         CallbackFree(CBPtr)
      If (RC) {
         This.ErrorMsg := StrGet(Err, "UTF-8")
         This.ErrorCode := RC
         DllCall("SQLite3.dll\sqlite3_free", "Ptr", Err, "Cdecl")
         Return False
      }
      This.Changes := This._Changes()
      Return True
   }

   GetTable(SQL, &TB, MaxResult := 0) {
      TB := ""
      This.ErrorMsg := ""
      This.ErrorCode := 0
      This.SQL := SQL
      If !(This._Handle)
         Return This._SetError(0, "Invalid database handle!")
      Local Names := ""
      Local Err := 0, GetRows := 0, RC := 0
      Local I := 0, Rows := Cols := 0
      Local Table := 0
      If !IsInteger(MaxResult)
         MaxResult := 0
      If (MaxResult < -2)
         MaxResult := 0
      Local UTF8 := This._StrToUTF8(SQL)
      RC := DllCall("SQlite3.dll\sqlite3_get_table", "Ptr", This._Handle, "Ptr", UTF8, "UPtrP", &Table,
                    "IntP", &Rows, "IntP", &Cols, "UPtrP", &Err, "Cdecl Int")
      If (RC) {
         This.ErrorMsg := StrGet(Err, "UTF-8")
         This.ErrorCode := RC
         DllCall("SQLite3.dll\sqlite3_free", "Ptr", Err, "Cdecl")
         Return False
      }
      TB := SQLiteDB._Table()
      TB.ColumnCount := Cols
      TB.RowCount := Rows
      If (MaxResult = -1) {
         DllCall("SQLite3.dll\sqlite3_free_table", "Ptr", Table, "Cdecl")
         Return True
      }
      If (MaxResult = -2)
         GetRows := 0
      Else If (MaxResult > 0) && (MaxResult <= Rows)
         GetRows := MaxResult
      Else
         GetRows := Rows
      Local Offset := 0
      Names := []
      Names.Length := Cols
      Loop Cols {
         Names[A_Index] := StrGet(NumGet(Table + Offset, "UPtr"), "UTF-8")
         Offset += A_PtrSize
      }
      TB.ColumnNames := Names
      TB.HasNames := True
      TB.Rows.Length := GetRows
      Local ColArr
      Loop GetRows {
         ColArr := []
         ColArr.Length := Cols
         Loop Cols {
            ColArr[A_Index] := (Pointer := NumGet(Table + Offset, "UPtr")) ? StrGet(Pointer, "UTF-8") : ""
            Offset += A_PtrSize
         }
         TB.Rows[A_Index] := ColArr
      }
      If (GetRows)
         TB.HasRows := True
      DllCall("SQLite3.dll\sqlite3_free_table", "Ptr", Table, "Cdecl")
      Return True
   }

   Prepare(SQL, &ST) {
      Local ColumnCount, ColumnNames, Pointer, RC
      This.ErrorMsg := ""
      This.ErrorCode := 0
      This.SQL := SQL
      If !(This._Handle)
         Return This._SetError(0, "Invalid database handle!")
      Local Stmt := 0
      Local UTF8 := This._StrToUTF8(SQL)
      RC := DllCall("SQlite3.dll\sqlite3_prepare_v2", "Ptr", This._Handle, "Ptr", UTF8, "Int", -1,
                    "UPtrP", &Stmt, "Ptr", 0, "Cdecl Int")
      If (RC)
         Return This._SetError(RC)
      ColumnNames := []
      ColumnCount := DllCall("SQlite3.dll\sqlite3_column_count", "Ptr", Stmt, "Cdecl Int")
      If (ColumnCount > 0) {
         ColumnNames.Length := ColumnCount
         Loop ColumnCount {
            Pointer := DllCall("SQlite3.dll\sqlite3_column_name", "Ptr", Stmt, "Int", A_Index - 1, "Cdecl UPtr")
            ColumnNames[A_Index] := StrGet(Pointer, "UTF-8")
         }
      }
		ST := SQLiteDB._Prepared()
      ST.ColumnCount := ColumnCount
      ST.ColumnNames := ColumnNames
      ST.ParamCount := DllCall("SQlite3.dll\sqlite3_bind_parameter_count", "Ptr", Stmt, "Cdecl Int")
      ST._Handle := Stmt
      ST._DB := This
      This._Stmts[Stmt] := Stmt
      Return True
   }

   CreateScalarFunc(Name, Args, Func, Enc := 0x0801, Param := 0) {
      ; SQLITE_DETERMINISTIC = 0x0800 - the function will always return the same result given the same inputs
      ;                                 within a single SQL statement
      ; SQLITE_UTF8 = 0x0001
      This.ErrorMsg := ""
      This.ErrorCode := 0
      If !(This._Handle)
         Return This._SetError(0, "Invalid database handle!")
      Local RC := DllCall("SQLite3.dll\sqlite3_create_function", "Ptr", This._Handle, "AStr", Name, "Int", Args,
                          "Int", Enc, "Ptr", Param, "Ptr", Func, "Ptr", 0, "Ptr", 0, "Cdecl Int")
      Return (RC) ? This._SetError(RC) : True
   }

   EnableLoadExtension(Enable := 1) {
      Local RC := DllCall("SQLite3.dll\sqlite3_db_config", "Ptr", This._Handle, "Int", 1005, "Int", !!Enable,
                          "Ptr", 0, "Cdecl Int")
      Return (RC) ? This._SetError(RC) : True
   }

   LoadExtension(File, Proc?) {
      Local RC := IsSet(Proc) ? DllCall("SQLite3.dll\sqlite3_load_extension", "Ptr", This._Handle, "AStr", File,
                                        "AStr", Proc, "Ptr", 0, "Cdecl Int")
                              : DllCall("SQLite3.dll\sqlite3_load_extension", "Ptr", This._Handle, "AStr", File,
                                        "Ptr", 0, "Ptr", 0, "Cdecl Int")
      Return (RC) ? This._SetError(RC) : True
   }

   LastInsertRowID(&RowID) {
      This.ErrorMsg := ""
      This.ErrorCode := 0
      This.SQL := ""
      If !(This._Handle)
         Return This._SetError(0, "Invalid database handle!")
      RowID := DllCall("SQLite3.dll\sqlite3_last_insert_rowid", "Ptr", This._Handle, "Cdecl Int64")
      Return True
   }

   TotalChanges(&Rows) {
      This.ErrorMsg := ""
      This.ErrorCode := 0
      This.SQL := ""
      If !(This._Handle)
         Return This._SetError(0, "Invalid database handle!")
      Rows := DllCall("SQLite3.dll\sqlite3_total_changes", "Ptr", This._Handle, "Cdecl Int")
      Return True
   }

   SetTimeout(Timeout := 1000) {
      Local RC
      This.ErrorMsg := ""
      This.ErrorCode := 0
      This.SQL := ""
      If !(This._Handle)
         Return This._SetError(0, "Invalid database handle!")
      If !IsInteger(Timeout)
         Timeout := 1000
      If (RC := DllCall("SQLite3.dll\sqlite3_busy_timeout", "Ptr", This._Handle, "Int", Timeout, "Cdecl Int"))
         Return This._SetError(RC)
      Return True
   }

   EscapeStr(&Str, Quote := True) {
      This.ErrorMsg := ""
      This.ErrorCode := 0
      This.SQL := ""
      If !(This._Handle)
         Return This._SetError(0, "Invalid database handle!")
      If IsNumber(Str)
         Return True
      Local OP := Buffer(16, 0)
      StrPut(Quote ? "%Q" : "%q", OP, "UTF-8")
      Local UTF8 := This._StrToUTF8(Str)
      Local Ptr := DllCall("SQLite3.dll\sqlite3_mprintf", "Ptr", OP, "Ptr", UTF8, "Cdecl UPtr")
      Str := StrGet(Ptr, "UTF-8")
      DllCall("SQLite3.dll\sqlite3_free", "Ptr", Ptr, "Cdecl")
      Return True
   }

   ExtErrCode() {
      If !(This._Handle)
         Return 0
      Return DllCall("SQLite3.dll\sqlite3_extended_errcode", "Ptr", This._Handle, "Cdecl Int")
   }

   _Changes() {
      Return DllCall("SQLite3.dll\sqlite3_changes", "Ptr", This._Handle, "Cdecl Int")
   }

   _ErrMsg() {
      Local RC
      If (RC := DllCall("SQLite3.dll\sqlite3_errmsg", "Ptr", This._Handle, "Cdecl UPtr"))
         Return StrGet(RC, "UTF-8")
      Return ""
   }

   _ErrCode() {
      Return DllCall("SQLite3.dll\sqlite3_errcode", "Ptr", This._Handle, "Cdecl Int")
   }

   _ErrStr(ErrCode) {
      Return StrGet(DllCall("SQLite3.dll\sqlite3_errstr", "Int", ErrCode, "Cdecl UPtr"), "UTF-8")
   }

   _SetError(RC, Msg?) {
      This.ErrorMsg := IsSet(Msg) ? Msg : This._ErrMsg()
      This.ErrorCode := RC
      Return False
   }

   _StrToUTF8(Str) {
      Local UTF8 := Buffer(StrPut(Str, "UTF-8"), 0)
      StrPut(Str, UTF8, "UTF-8")
      Return UTF8
   }

   _ReturnCode(RC) {
      Static RCODE := {SQLITE_OK:           0, ; Successful result
                       SQLITE_ERROR:        1, ; SQL error or missing database
                       SQLITE_INTERNAL:     2, ; NOT USED. Internal logic error in SQLite
                       SQLITE_PERM:         3, ; Access permission denied
                       SQLITE_ABORT:        4, ; Callback routine requested an abort
                       SQLITE_BUSY:         5, ; The database file is locked
                       SQLITE_LOCKED:       6, ; A table in the database is locked
                       SQLITE_NOMEM:        7, ; A malloc() failed
                       SQLITE_READONLY:     8, ; Attempt to write a readonly database
                       SQLITE_INTERRUPT:    9, ; Operation terminated by sqlite3_interrupt()
                       SQLITE_IOERR:       10, ; Some kind of disk I/O error occurred
                       SQLITE_CORRUPT:     11, ; The database disk image is malformed
                       SQLITE_NOTFOUND:    12, ; NOT USED. Table or record not found
                       SQLITE_FULL:        13, ; Insertion failed because database is full
                       SQLITE_CANTOPEN:    14, ; Unable to open the database file
                       SQLITE_PROTOCOL:    15, ; NOT USED. Database lock protocol error
                       SQLITE_EMPTY:       16, ; Database is empty
                       SQLITE_SCHEMA:      17, ; The database schema changed
                       SQLITE_TOOBIG:      18, ; String or BLOB exceeds size limit
                       SQLITE_CONSTRAINT:  19, ; Abort due to constraint violation
                       SQLITE_MISMATCH:    20, ; Data type mismatch
                       SQLITE_MISUSE:      21, ; Library used incorrectly
                       SQLITE_NOLFS:       22, ; Uses OS features not supported on host
                       SQLITE_AUTH:        23, ; Authorization denied
                       SQLITE_FORMAT:      24, ; Auxiliary database format error
                       SQLITE_RANGE:       25, ; 2nd parameter to sqlite3_bind out of range
                       SQLITE_NOTADB:      26, ; File opened that is not a database file
                       SQLITE_ROW:        100, ; sqlite3_step() has another row ready
                       SQLITE_DONE:       101} ; sqlite3_step() has finished executing
      Return RCODE.HasOwnProp(RC) ? RCODE.%RC% : ""
   }



   Class _Table {

      __New() {
          This.ColumnCount := 0          ; Number of columns in the result table         (Integer)
          This.RowCount := 0             ; Number of rows in the result table            (Integer)
          This.ColumnNames := []         ; Names of columns in the result table          (Array)
          This.Rows := []                ; Rows of the result table                      (Array of Arrays)
          This.HasNames := False         ; Does var ColumnNames contain names?           (Bool)
          This.HasRows := False          ; Does var Rows contain rows?                   (Bool)
          This._CurrentRow := 0          ; Row index of last returned row                (Integer)
      }

      GetRow(RowIndex, &Row) {
         Row := ""
         If (RowIndex < 1 || RowIndex > This.RowCount)
            Return False
         If !This.Rows.Has(RowIndex)
            Return False
         Row := This.Rows[RowIndex]
         This._CurrentRow := RowIndex
         Return True
      }

      Next(&Row) {
         Row := ""
         If (This._CurrentRow >= This.RowCount)
            Return -1
         This._CurrentRow += 1
         If !This.Rows.Has(This._CurrentRow)
            Return False
         Row := This.Rows[This._CurrentRow]
         Return True
      }

      Reset() {
         This._CurrentRow := 0
         Return True
      }
   }

   Class _Prepared {
      ; ----------------------------------------------------------------------------------------------------------------
      ; CONSTRUCTOR  Create instance variables
      ; ----------------------------------------------------------------------------------------------------------------
      __New() {
         This.ColumnCount := 0         ; Number of columns in the result               (Integer)
         This.ColumnNames := []        ; Names of columns in the result                (Array)
         This.CurrentStep := 0         ; Index of current step                         (Integer)
         This.ErrorMsg := ""           ; Last error message                            (String)
         This.ErrorCode := 0           ; Last SQLite error code / ErrorLevel           (Variant)
         This._Handle := 0             ; Query handle                                  (Pointer)
         This._DB := {}                ; SQLiteDB object                               (Object)
      }
      ; ----------------------------------------------------------------------------------------------------------------
      ; DESTRUCTOR   Clear instance variables
      ; ----------------------------------------------------------------------------------------------------------------
      __Delete() {
         If This.HasOwnProp("_Handle") && (This._Handle != 0)
            This.Free()
      }

      Bind(Params) {
         Static Types := {Blob: 1, Double: 1, Int: 1, Int64: 1, Null: 1, Text: 1}
         Local Index, Param, ParamType, RC, UTF8, Value
         This.ErrorMsg := ""
         This.ErrorCode := 0
         If !(This._Handle) {
            This.ErrorMsg := "Invalid statement handle!"
            Return False
         }
         For Index, Param In Params {
            If (Index < 1) || (Index > This.ParamCount)
               Return This._SetError(0, "Invalid parameter index: " . Index . "!")
            For ParamType, Value In Param {
               If !Types.HasOwnProp(ParamType)
                  Return This._SetError(0, "Invalid parameter type " . ParamType . " at index " Index . "!")
               Switch ParamType {
                  Case "Blob":
                     ; Value = Buffer object
                     If !(ParamType(Value) = "Buffer")
                        Return This._SetError(0, "Invalid blob object at index " . Index . "!")
                     ; Let SQLite always create a copy of the BLOB
                     RC := DllCall("SQlite3.dll\sqlite3_bind_blob", "Ptr", This._Handle, "Int", Index, "Ptr", Value,
                                   "Int", Value.Size, "Ptr", -1, "Cdecl Int")
                     If (RC)
                        Return This._SetError(RC)
                  Case "Double":
                     ; Value = double value
                     If !IsFloat(Value)
                        Return This._SetError(0, "Invalid value for double at index " . Index . "!")
                     RC := DllCall("SQlite3.dll\sqlite3_bind_double", "Ptr", This._Handle, "Int", Index, "Double", Value,
                                   "Cdecl Int")
                     If (RC)
                        Return This._SetError(RC)
                  Case "Int":
                     ; Value = integer value
                     If !IsInteger(Value)
                        Return This._SetError(0, "Invalid value for int at index " . Index . "!")
                     RC := DllCall("SQlite3.dll\sqlite3_bind_int", "Ptr", This._Handle, "Int", Index, "Int", Value,
                                   "Cdecl Int")
                     If (RC)
                        Return This._SetError(RC)
                  Case "Int64":
                     ; Value = integer value
                     If !IsInteger(Value)
                        Return This._SetError(0, "Invalid value for int64 at index " . Index . "!")
                     RC := DllCall("SQlite3.dll\sqlite3_bind_int64", "Ptr", This._Handle, "Int", Index, "Int64", Value,
                                   "Cdecl Int")
                     If (RC)
                        Return This._SetError(RC)
                  Case "Null":
                     RC := DllCall("SQlite3.dll\sqlite3_bind_null", "Ptr", This._Handle, "Int", Index, "Cdecl Int")
                     If (RC)
                        Return This._SetError(RC)
                  Case "Text":
                     ; Value = zero-terminated string
                     UTF8 := This._DB._StrToUTF8(Value)
                     ; Let SQLite always create a copy of the text
                     RC := DllCall("SQlite3.dll\sqlite3_bind_text", "Ptr", This._Handle, "Int", Index, "Ptr", UTF8,
                                   "Int", -1, "Ptr", -1, "Cdecl Int")
                     If (RC)
                        Return This._SetError(RC)
               }
               Break
            }
         }
         Return True
      }

      Step(Row?) { ; !!!!! Note: If Row is not omitted is must be a VarRef !!!!!
         Static SQLITE_INTEGER := 1, SQLITE_FLOAT := 2, SQLITE_BLOB := 4, SQLITE_NULL := 5
         Static EOR := -1
         Local Blob, BlobPtr, BlobSize, Column, ColumnType, RC, Res, Value
         If IsSet(Row) && !(Row Is VarRef)
            Throw TypeError("Parameter #1 requires a variable reference, but received a" .
                            (Type(Row) ~= "i)^[aeiou]" ? "n " : " ") . Type(Row) ".", -1, Row)
         This.ErrorMsg := ""
         This.ErrorCode := 0
         If !(This._Handle)
            Return This._SetError(0, "Invalid query handle!")
         RC := DllCall("SQlite3.dll\sqlite3_step", "Ptr", This._Handle, "Cdecl Int")
         If (RC = This._DB._ReturnCode("SQLITE_DONE"))
            Return (This._SetError(RC, "EOR") | EOR)
         If (RC != This._DB._ReturnCode("SQLITE_ROW"))
            Return This._SetError(RC)
         This.CurrentStep += 1
         If !IsSet(Row)
            Return True
         Res := []
         RC := DllCall("SQlite3.dll\sqlite3_data_count", "Ptr", This._Handle, "Cdecl Int")
         If (RC < 1)
            Return True
         Res.Length := RC
         Loop RC {
            Column := A_Index - 1
            ColumnType := DllCall("SQlite3.dll\sqlite3_column_type", "Ptr", This._Handle, "Int", Column, "Cdecl Int")
            Switch ColumnType {
               Case SQLITE_BLOB:
                  BlobPtr := DllCall("SQlite3.dll\sqlite3_column_blob", "Ptr", This._Handle, "Int", Column, "Cdecl UPtr")
                  BlobSize := DllCall("SQlite3.dll\sqlite3_column_bytes", "Ptr", This._Handle, "Int", Column, "Cdecl Int")
                  If (BlobPtr = 0) || (BlobSize = 0)
                     Res[A_Index] := ""
                  Else {
                     Blob := Buffer(BlobSize)
                     DllCall("Kernel32.dll\RtlMoveMemory", "Ptr", Blob, "Ptr", BlobPtr, "Ptr", BlobSize)
                     Res[A_Index] := Blob
                  }
               Case SQLITE_INTEGER:
                  Value := DllCall("SQlite3.dll\sqlite3_column_int64", "Ptr", This._Handle, "Int", Column, "Cdecl Int64")
                  Res[A_Index] := Value
               Case SQLITE_FLOAT:
                  Value := DllCall("SQlite3.dll\sqlite3_column_double", "Ptr", This._Handle, "Int", Column, "Cdecl Double")
                  Res[A_Index] := Value
               Case SQLITE_NULL:
                  Res[A_Index] := ""
               Default:
                  Value := DllCall("SQlite3.dll\sqlite3_column_text", "Ptr", This._Handle, "Int", Column, "Cdecl UPtr")
                  Res[A_Index] := StrGet(Value, "UTF-8")
            }
         }
         %Row% := Res
         Return True
      }

      Next(Row?) { ; !!!!! Note: If Row is not omitted is must be a VarRef !!!!!
         If !IsSet(Row)
            Return This.Step()
         If Row Is VarRef
            Return This.Step(Row)
         Throw TypeError("Parameter #1 requires a variable reference, but received a" .
                         (Type(Row) ~= "i)^[aeiou]" ? "n " : " ") . Type(Row) ".", -1, Row)
      }

      Reset(ClearBindings := True) {
         Local RC
         This.ErrorMsg := ""
         This.ErrorCode := 0
         If !(This._Handle)
            Return This._SetError(0, "Invalid query handle!")
         If (RC := DllCall("SQlite3.dll\sqlite3_reset", "Ptr", This._Handle, "Cdecl Int"))
            Return This._SetError(RC)
         If (ClearBindings) && (RC := DllCall("SQlite3.dll\sqlite3_clear_bindings", "Ptr", This._Handle, "Cdecl Int"))
            Return This._SetError(RC)
         This.CurrentStep := 0
         Return True
      }

      Free() {
         Local RC
         This.ErrorMsg := ""
         This.ErrorCode := 0
         If !(This._Handle)
            Return True
         If (RC := DllCall("SQlite3.dll\sqlite3_finalize", "Ptr", This._Handle, "Cdecl Int"))
            Return This._SetError(RC)
         This._DB._Stmts.Delete(This._Handle)
         This._Handle := 0
         This._DB := 0
         Return True
      }

      _SetError(RC, Msg?) {
         This.ErrorMsg := IsSet(Msg) ? Msg : This._DB._ErrMsg()
         This.ErrorCode := RC
         Return False
      }
   }
}

SQLiteDB_RegExp(Context, ArgC, Values) {
   Local AddrH, AddrN, Result := 0
   If (ArgC = 2) {
      AddrN := DllCall("SQLite3.dll\sqlite3_value_text", "Ptr", NumGet(Values + 0, "UPtr"), "Cdecl UPtr")
      AddrH := DllCall("SQLite3.dll\sqlite3_value_text", "Ptr", NumGet(Values + A_PtrSize, "UPtr"), "Cdecl UPtr")
      Result := RegExMatch(StrGet(AddrH, "UTF-8"), StrGet(AddrN, "UTF-8"))
   }
   DllCall("SQLite3.dll\sqlite3_result_int", "Ptr", Context, "Int", !!Result, "Cdecl") ; 0 = false, 1 = true
}