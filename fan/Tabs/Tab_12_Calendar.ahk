; ===============================================================================
; Tabs\Tab_12_Calendar.ahk
; TAB 12 Calendar: appointment scheduler, patients
; Extracted from macroautomaterv9-deepseek.ahk - not a standalone script:
; it is #Include'd by MacroAutomator.ahk. See SPLIT_MANIFEST.md for ranges.
; ===============================================================================

ClickTimeSlot(time, *) {
    global g_CalendarDate, g_Appointments

    appointment := GetAppointment(g_CalendarDate, time)
    if appointment.Count > 0 {
        choice := MsgBox(
            CalendarAppointmentText(appointment) . "`n`nYes = edit/rebook`nNo = cancel appointment`nCancel = keep it",
            "Appointment at " . FormatTimeSlot(time),
            "YesNoCancel Icon?"
        )
        if choice = "No" {
            CancelAppointment(g_CalendarDate, time)
            return
        }
        if choice != "Yes"
            return
    }
    OpenBookingDialog(time, appointment)
}

CalendarAppointmentText(appointment) {
    if !IsObject(appointment)
        return String(appointment)
    if appointment is Map {
        patient := appointment.Has("patientName") ? appointment["patientName"]
            : (appointment.Has("patient") ? appointment["patient"] : "Appointment")
        typeName := appointment.Has("typeName") ? appointment["typeName"]
            : (appointment.Has("type") ? appointment["type"] : "")
        return patient . (typeName != "" ? " - " . typeName : "")
    }
    return "Appointment"
}

PrevDay(*) {
    global g_CalendarDate
    g_CalendarDate := DateAdd(g_CalendarDate, -1, "Days")
    RefreshCalendar()
}

NextDay(*) {
    global g_CalendarDate
    g_CalendarDate := DateAdd(g_CalendarDate, 1, "Days")
    RefreshCalendar()
}

GoToToday(*) {
    global g_CalendarDate
    g_CalendarDate := FormatTime(, "yyyyMMdd")
    RefreshCalendar()
}

RefreshCalendar(*) {
    global g_CalendarDate, g_CalendarSlotButtons, g_Appointments, DateText
    DateText.Text := FormatTime(g_CalendarDate, "dddd, MMMM d, yyyy")
    for time, button in g_CalendarSlotButtons {
        key := GetAppointmentKey(g_CalendarDate, time)
        button.Text := g_Appointments.Has(key)
            ? CalendarAppointmentText(g_Appointments[key])
            : "[Empty]"
    }
}

UpdateTaskPreview(typeDD, presetCheckboxes, taskPreviewEdit) {
    ; Combine appointment type tasks + selected preset tasks
    allTasks := []

    ; Get appointment type tasks
    typeName := typeDD.Text
    for key, typeInfo in g_AppointmentTypes {
        if (typeInfo["name"] = typeName) {
            for task in typeInfo["tasks"] {
                allTasks.Push(task)
            }
            break
        }
    }

    ; Get selected preset tasks
    for presetInfo in presetCheckboxes {
        if (presetInfo["control"].Value) {  ; If checked
            presetKey := presetInfo["key"]
            preset := g_TaskPresets[presetKey]
            for task in preset["tasks"] {
                allTasks.Push(task)
            }
        }
    }

    ; Sort by time
    ; (Sort allTasks by notifyBefore in descending order)

    ; Display
    preview := ""
    for task in allTasks {
        minutes := task["notifyBefore"]
        if (minutes > 0) {
            preview .= "⏰ " . minutes . " min before: " . task["task"] . "`n"
        } else {
            preview .= "⏰ At appointment: " . task["task"] . "`n"
        }
    }
    taskPreviewEdit.Value := preview
}

Tab_Calendar_Build() {
    global btn, DateText, slots, yPos
    TabCtrl.UseTab(12)

    MainGui.Add("Text", "x15 y50", "📅 Appointment Scheduler")
    MainGui.Add("Button", "x150 y50 w60 h25", "◄ Prev").OnEvent("Click", PrevDay)
    global DateText := MainGui.Add("Text", "x215 y55 w200 Center", FormatTime(g_CalendarDate, "dddd, MMMM d, yyyy"))
    MainGui.Add("Button", "x420 y50 w60 h25", "Next ►").OnEvent("Click", NextDay)
    MainGui.Add("Button", "x490 y50 w60 h25", "Today").OnEvent("Click", GoToToday)
    MainGui.Add("Button", "x560 y50 w85 h25", "Patients").OnEvent("Click", OpenPatientList)

    ; Time slots (create one button per slot)
    yPos := 90
    slots := GenerateTimeSlots()

    for slotTime in slots {
        ; Time label
        MainGui.Add("Text", "x15 y" . yPos, slotTime)

        ; Appointment slot button
        btn := MainGui.Add("Button", "x70 y" . (yPos-3) . " w650 h28", "[Empty]")
        btn.OnEvent("Click", ClickTimeSlot.Bind(slotTime))
        g_CalendarSlotButtons[slotTime] := btn

        yPos += 30
    }

    ; Calendar data is optional and must never prevent core workflow/template startup.
    try InitializeAppointmentScheduler()
    catch as err
        LogErrorToFile(err, "caught", "Optional appointment scheduler initialization")
    try RefreshCalendar()
    catch as err
        LogErrorToFile(err, "caught", "Optional appointment calendar refresh")

}


ClickTimeSlot2(time) {
    ; Show input box for patient name and appointment type
    result := InputBox("Enter: Patient Name | Appointment Type",
                       "Book Appointment at " . time,
                       "w400 h150")

    if (result.Result = "OK") {
        ; Save appointment
        key := g_CalendarDate . "_" . StrReplace(time, ":", "")
        g_Appointments[key] := result.Value

        ; Create notification
        CreateSimpleNotification(g_CalendarDate, time, result.Value)

        ; Refresh display
        RefreshCalendar()
        SaveAppointments()
    }
}
CreateSimpleNotification(date, time, appointmentInfo) {
    ; Schedule notification at appointment time
    triggerTime := date . " " . time

    ; Add to existing notification system
    title := "Appointment"
    message := appointmentInfo

    ; Store for monitoring
    ; (Use existing notification system from Tab 4)
}

SaveAppointments() {
    global g_Appointments, DATA_DIR
    iniFile := A_ScriptDir . "\Data\appointments.ini"
    if !DirExist(DATA_DIR)
        DirCreate(DATA_DIR)
    if FanFileExist(iniFile)
        FanFileDelete(iniFile)

    FanIniWrite(7, iniFile, "Meta", "Version")
    for key, appointment in g_Appointments {
        section := "Appointment_" . key
        if IsObject(appointment) && appointment is Map {
            FanIniWrite(appointment.Has("date") ? appointment["date"] : SubStr(key, 1, 8), iniFile, section, "Date")
            FanIniWrite(appointment.Has("time") ? appointment["time"] : "", iniFile, section, "Time")
            FanIniWrite(appointment.Has("patientID") ? appointment["patientID"] : 0, iniFile, section, "PatientID")
            FanIniWrite(appointment.Has("patientName") ? appointment["patientName"] : CalendarAppointmentText(appointment), iniFile, section, "PatientName")
            FanIniWrite(appointment.Has("appointmentType") ? appointment["appointmentType"] : "", iniFile, section, "AppointmentType")
            FanIniWrite(appointment.Has("typeName") ? appointment["typeName"] : "", iniFile, section, "TypeName")
            FanIniWrite(appointment.Has("status") ? appointment["status"] : "Scheduled", iniFile, section, "Status")
        } else {
            FanIniWrite(SubStr(key, 1, 8), iniFile, section, "Date")
            FanIniWrite("", iniFile, section, "Time")
            FanIniWrite(String(appointment), iniFile, section, "PatientName")
            FanIniWrite("Legacy", iniFile, section, "Status")
        }
    }
}

LoadAppointments() {
    global g_Appointments, g_AppointmentTypes
    iniFile := A_ScriptDir . "\Data\appointments.ini"
    if !FanFileExist(iniFile)
        return

    g_Appointments := Map()
    sections := ""
    try sections := FanIniRead(iniFile)
    for section in StrSplit(sections, "`n", "`r") {
        section := Trim(section)
        if InStr(section, "Appointment_") != 1
            continue
        date := FanIniRead(iniFile, section, "Date", "")
        time := FanIniRead(iniFile, section, "Time", "")
        patientIDText := FanIniRead(iniFile, section, "PatientID", "0")
        patientName := FanIniRead(iniFile, section, "PatientName", "")
        appointmentType := FanIniRead(iniFile, section, "AppointmentType", "")
        typeName := FanIniRead(iniFile, section, "TypeName", "")
        status := FanIniRead(iniFile, section, "Status", "Scheduled")
        if date = "" {
            keyFromSection := SubStr(section, 13)
            date := SubStr(keyFromSection, 1, 8)
        }
        if time = "" {
            keyFromSection := SubStr(section, 13)
            cleanTime := SubStr(keyFromSection, 10, 4)
            if StrLen(cleanTime) = 4
                time := SubStr(cleanTime, 1, 2) . ":" . SubStr(cleanTime, 3, 2)
        }
        if date = "" || time = ""
            continue
        typeInfo := g_AppointmentTypes.Has(appointmentType) ? g_AppointmentTypes[appointmentType] : Map("duration", 30, "tasks", [])
        key := GetAppointmentKey(date, time)
        g_Appointments[key] := Map(
            "date", date, "time", time,
            "patientID", IsNumber(patientIDText) ? Integer(patientIDText) : 0,
            "patientName", patientName,
            "appointmentType", appointmentType,
            "typeName", typeName,
            "duration", typeInfo["duration"],
            "tasks", typeInfo["tasks"],
            "status", status
        )
    }

    ; Backward compatibility with the repaired v6.1 single-section format.
    if g_Appointments.Count = 0 {
        try sectionText := FanIniRead(iniFile, "Appointments")
        catch
            sectionText := ""
        Loop Parse, sectionText, "`n", "`r" {
            line := Trim(A_LoopField)
            separator := InStr(line, "=")
            if separator {
                key := Trim(SubStr(line, 1, separator - 1))
                info := SubStr(line, separator + 1)
                if key != ""
                    g_Appointments[key] := info
            }
        }
    }
}

BookAppointmentWithTasks(date, time, patientID, appointmentType) {
    ; Get patient name
    patient := g_Patients[patientID]
    patientName := patient["name"]

    ; Get appointment type details
    typeInfo := g_AppointmentTypes[appointmentType]

    ; Create appointment
    key := date . "_" . StrReplace(time, ":", "")
    appointmentInfo := patientName . " - " . typeInfo["name"]
    g_Appointments[key] := Map(
        "patient", patientName,
        "type", appointmentType,
        "tasks", typeInfo["tasks"]
    )

    ; Generate notification for each task
    appointmentDateTime := date . StrReplace(time, ":", "") . "00"

    for task in typeInfo["tasks"] {
        notifyMinutes := task["notifyBefore"]

        ; Calculate trigger time
        triggerTime := DateAdd(appointmentDateTime, -notifyMinutes, "Minutes")

        ; Create notification
        message := patientName . " - " . task["task"]
        CreateScheduledNotification(triggerTime, "Appointment Task", message)
    }

    SaveAppointments()
    RefreshCalendar()
}

CreateScheduledNotification(triggerTime, title, message) {
    secondsUntil := DateDiff(triggerTime, A_Now, "Seconds")
    if secondsUntil <= 0 {
        ShowNotificationBasic(title, message, 0, "info")
        return true
    }

    ; AutoHotkey timer periods are practical up to about 24 days in milliseconds.
    if secondsUntil <= 2147483 {
        SetTimer((*) => ShowNotificationBasic(title, message, 0, "info"),
                 -(secondsUntil * 1000))
        return true
    }

    LogDiagnostic("Scheduled notification is more than 24 days away: " . triggerTime,
                  "Appointment notification", "INFO")
    return false
}

ConfirmBooking(time, patientDD, typeDD, bookGui, *) {
    return BookAppointment(time, patientDD, typeDD, bookGui)
}
ClickTimeSlot3(time) {
    BookGui := Gui("+OwnerMainGui", "Book Appointment at " . time)

    ; Patient selection
    BookGui.Add("Text", "x10 y10", "Patient:")
    patientNames := GetPatientNames()
    patientDD := BookGui.Add("DropDownList", "x70 y10 w200", patientNames)

    ; Appointment type selection
    BookGui.Add("Text", "x10 y40", "Type:")
    typeNames := []
    for key, typeInfo in g_AppointmentTypes {
        typeNames.Push(typeInfo["name"])
    }
    typeDD := BookGui.Add("DropDownList", "x70 y40 w200", typeNames)
    typeDD.OnEvent("Change", (*) => ShowTaskPreview(typeDD, taskPreviewEdit))

    ; Task preview
    BookGui.Add("Text", "x10 y70", "Tasks that will be scheduled:")
    taskPreviewEdit := BookGui.Add("Edit", "x10 y90 w350 h150 ReadOnly Multi")

    ; Buttons
    BookGui.Add("Button", "x70 y250 w100 h25", "Book").OnEvent("Click", (*) => ConfirmBooking(time, patientDD, typeDD, BookGui))
    BookGui.Add("Button", "x180 y250 w100 h25", "Cancel").OnEvent("Click", (*) => BookGui.Destroy())

    BookGui.Show("w370 h290")
}

ShowTaskPreview(typeDD, taskPreviewEdit) {
    ; Get selected appointment type
    selectedIndex := typeDD.Value
    typeName := typeDD.Text

    ; Find matching type
    for key, typeInfo in g_AppointmentTypes {
        if (typeInfo["name"] = typeName) {
            ; Build task preview text
            preview := ""
            for task in typeInfo["tasks"] {
                minutes := task["notifyBefore"]
                if (minutes > 0) {
                    preview .= "⏰ " . minutes . " min before: " . task["task"] . "`n"
                } else {
                    preview .= "⏰ At appointment: " . task["task"] . "`n"
                }
            }
            taskPreviewEdit.Value := preview
            break
        }
    }
}
InitializeTaskPresets() {
    ; New Patient Setup
    g_TaskPresets["NewPatientSetup"] := Map(
        "name", "New Patient Setup",
        "tasks", [
            Map("task", "Scan insurance card", "notifyBefore", 15),
            Map("task", "Enter into web app", "notifyBefore", 10),
            Map("task", "Verify name ALL CAPS", "notifyBefore", 5)
        ]
    )

    ; Payment Processing
    g_TaskPresets["Payment"] := Map(
        "name", "Payment Processing",
        "tasks", [
            Map("task", "Get credit card on file", "notifyBefore", 10),
            Map("task", "Sign authorization", "notifyBefore", 5),
            Map("task", "Calculate co-pay", "notifyBefore", 5)
        ]
    )

    ; Insurance Verification
    g_TaskPresets["Insurance"] := Map(
        "name", "Insurance Verification",
        "tasks", [
            Map("task", "Verify insurance active", "notifyBefore", 10),
            Map("task", "Check coverage", "notifyBefore", 10)
        ]
    )
}


CreatePatient(name, phone := "", email := "", notes := "") {
    global g_NextPatientID, g_Patients
    id := g_NextPatientID++
    g_Patients[id] := Map(
        "id", id,
        "name", name,
        "phone", phone,
        "email", email,
        "notes", notes,
        "visitHistory", []
    )
    SavePatients()
    return id
}

SavePatients() {
    global g_Patients, g_NextPatientID, DATA_DIR
    patientFile := DATA_DIR . "\patients.ini"
    if FanFileExist(patientFile)
        FanFileDelete(patientFile)

    FanIniWrite(g_NextPatientID, patientFile, "Settings", "NextID")
    for id, patient in g_Patients {
        section := "Patient_" . id
        FanIniWrite(patient["name"], patientFile, section, "Name")
        FanIniWrite(patient["phone"], patientFile, section, "Phone")
        FanIniWrite(patient["email"], patientFile, section, "Email")
        FanIniWrite(patient["notes"], patientFile, section, "Notes")
        history := patient.Has("visitHistory") ? StrJoin(patient["visitHistory"], "|") : ""
        FanIniWrite(history, patientFile, section, "VisitHistory")
    }
}

LoadPatients() {
    global g_Patients, g_NextPatientID, DATA_DIR
    patientFile := DATA_DIR . "\patients.ini"
    g_Patients := Map()
    g_NextPatientID := 1
    if !FanFileExist(patientFile)
        return

    sections := FanIniRead(patientFile)
    highestID := 0
    for section in StrSplit(sections, "`n", "`r") {
        section := Trim(section)
        if InStr(section, "Patient_") = 1
            idText := SubStr(section, 9)
        else if InStr(section, "Patient") = 1
            idText := SubStr(section, 8)
        else
            continue
        if !IsNumber(idText)
            continue
        id := Integer(idText)
        history := []
        historyText := FanIniRead(patientFile, section, "VisitHistory", "")
        if historyText != ""
            for visitDate in StrSplit(historyText, "|")
                history.Push(visitDate)
        g_Patients[id] := Map(
            "id", id,
            "name", FanIniRead(patientFile, section, "Name", ""),
            "phone", FanIniRead(patientFile, section, "Phone", ""),
            "email", FanIniRead(patientFile, section, "Email", ""),
            "notes", FanIniRead(patientFile, section, "Notes", ""),
            "visitHistory", history
        )
        highestID := Max(highestID, id)
    }
    nextText := FanIniRead(patientFile, "Settings", "NextID", FanIniRead(patientFile, "Meta", "NextID", highestID + 1))
    g_NextPatientID := IsNumber(nextText) ? Max(Integer(nextText), highestID + 1) : highestID + 1
}

OpenNewPatientDialog(*) {
    OpenPatientProfileEditor(0)
}

SavePatientProfile(patientID, nameEdit, phoneEdit, emailEdit, notesEdit, profileGui, *) {
    global g_Patients, g_NextPatientID
    name := Trim(nameEdit.Value)
    if name = "" {
        MsgBox("Patient name is required.", "Patient Profile", "Icon!")
        return false
    }

    if patientID <= 0 {
        patientID := g_NextPatientID++
    }
    visitHistory := []
    if g_Patients.Has(patientID) && g_Patients[patientID].Has("visitHistory")
        visitHistory := g_Patients[patientID]["visitHistory"]
    g_Patients[patientID] := Map(
        "id", patientID,
        "name", name,
        "phone", phoneEdit.Value,
        "email", emailEdit.Value,
        "notes", notesEdit.Value,
        "visitHistory", visitHistory
    )
    SavePatients()
    profileGui.Destroy()
    ShowStatus("Patient profile saved: " . name, "ok")
    return true
}

BookAppointment(time, patientDD, typeDD, bookGui, *) {
    global g_CalendarDate, g_Appointments
    patientName := Trim(patientDD.Text)
    typeName := Trim(typeDD.Text)
    if patientName = "" || typeName = "" {
        MsgBox("Select both a patient and an appointment type.", "Book Appointment", "Icon!")
        return false
    }

    key := g_CalendarDate . "_" . StrReplace(time, ":", "")
    g_Appointments[key] := patientName . " - " . typeName
    SaveAppointments()
    RefreshCalendar()
    bookGui.Destroy()
    ShowStatus("Appointment booked for " . patientName . " at " . time, "ok")
    return true
}
ClickTimeSlot4(time) {
    ; Create dialog GUI
    BookGui := Gui("+OwnerMainGui", "Book Appointment")

    BookGui.Add("Text", "x10 y10", "Patient:")
    patientNames := GetPatientNames()
    patientDD := BookGui.Add("DropDownList", "x70 y10 w200", patientNames)
    BookGui.Add("Button", "x275 y10 w80 h25", "New Patient").OnEvent("Click", (*) => OpenNewPatientDialog())

    BookGui.Add("Text", "x10 y40", "Type:")
    typeDD := BookGui.Add("DropDownList", "x70 y40 w200", [
        "Contact Lens Exam",
        "Regular Eye Exam",
        "New Patient",
        "Medical Visit"
    ])

    BookGui.Add("Button", "x70 y80 w80 h25", "Book").OnEvent("Click", (*) => BookAppointment(time, patientDD, typeDD, BookGui))
    BookGui.Add("Button", "x160 y80 w80 h25", "Cancel").OnEvent("Click", (*) => BookGui.Destroy())

    BookGui.Show()
}
OpenPatientProfileEditor(patientID := 0) {
    ProfileGui := Gui("+OwnerMainGui", "Patient Profile")

    ; Load existing patient or create blank
    if (patientID > 0) {
        patient := g_Patients[patientID]
        name := patient["name"]
        phone := patient["phone"]
        email := patient["email"]
        notes := patient["notes"]
    } else {
        name := ""
        phone := ""
        email := ""
        notes := ""
    }

    ProfileGui.Add("Text", "x10 y10", "Name:")
    nameEdit := ProfileGui.Add("Edit", "x70 y10 w250", name)

    ProfileGui.Add("Text", "x10 y40", "Phone:")
    phoneEdit := ProfileGui.Add("Edit", "x70 y40 w250", phone)

    ProfileGui.Add("Text", "x10 y70", "Email:")
    emailEdit := ProfileGui.Add("Edit", "x70 y70 w250", email)

    ProfileGui.Add("Text", "x10 y100", "Notes:")
    notesEdit := ProfileGui.Add("Edit", "x70 y100 w250 h80 Multi", notes)

    ProfileGui.Add("Button", "x70 y190 w80 h25", "Save").OnEvent("Click", (*) => SavePatientProfile(patientID, nameEdit, phoneEdit, emailEdit, notesEdit, ProfileGui))
    ProfileGui.Add("Button", "x160 y190 w80 h25", "Cancel").OnEvent("Click", (*) => ProfileGui.Destroy())

    ProfileGui.Show()
}
InitializeAppointmentTypes() {
    global g_AppointmentTypes
    g_AppointmentTypes := Map()
    g_AppointmentTypes["ContactLens"] := Map(
        "name", "Contact Lens Exam",
        "duration", 30,
        "color", "Green",
        "tasks", [
            Map("task", "Verify contact lens prescription", "notifyBefore", 5),
            Map("task", "Prepare trial lenses", "notifyBefore", 10),
            Map("task", "Check lens fit and comfort", "notifyBefore", 0),
            Map("task", "Provide care instructions", "notifyBefore", 0),
            Map("task", "Order new supply if needed", "notifyBefore", 0)
        ]
    )
    g_AppointmentTypes["RegularExam"] := Map(
        "name", "Regular Eye Exam",
        "duration", 45,
        "color", "Blue",
        "tasks", [
            Map("task", "Pull previous records", "notifyBefore", 10),
            Map("task", "Dilate pupils if needed", "notifyBefore", 5),
            Map("task", "Perform vision tests", "notifyBefore", 0),
            Map("task", "Check eye health", "notifyBefore", 0),
            Map("task", "Discuss prescription changes", "notifyBefore", 0)
        ]
    )
    g_AppointmentTypes["NewPatient"] := Map(
        "name", "New Patient Intake",
        "duration", 60,
        "color", "Red",
        "tasks", [
            Map("task", "Scan insurance information", "notifyBefore", 15),
            Map("task", "Enter insurance into web app profile", "notifyBefore", 10),
            Map("task", "Verify all data is correct", "notifyBefore", 5),
            Map("task", "Ensure name is ALL CAPS in system", "notifyBefore", 5),
            Map("task", "Complete medical history form", "notifyBefore", 0),
            Map("task", "Take patient photos", "notifyBefore", 0),
            Map("task", "Create patient folder", "notifyBefore", 0)
        ]
    )
    g_AppointmentTypes["Medical"] := Map(
        "name", "Medical Visit",
        "duration", 30,
        "color", "Maroon",
        "tasks", [
            Map("task", "Get credit card on file", "notifyBefore", 10),
            Map("task", "Have patient sign payment authorization", "notifyBefore", 5),
            Map("task", "Determine co-pay amount", "notifyBefore", 5),
            Map("task", "Verify insurance is active", "notifyBefore", 5),
            Map("task", "Review chief complaint", "notifyBefore", 0),
            Map("task", "Document visit in EMR", "notifyBefore", 0),
            Map("task", "Process payment", "notifyBefore", 0)
        ]
    )
    g_AppointmentTypes["FollowUp"] := Map(
        "name", "Follow-Up Visit",
        "duration", 15,
        "color", "Purple",
        "tasks", [
            Map("task", "Review previous visit notes", "notifyBefore", 5),
            Map("task", "Check on prescribed treatment", "notifyBefore", 0),
            Map("task", "Update treatment plan", "notifyBefore", 0)
        ]
    )
}

InitializeAppointmentScheduler() {
    InitializeAppointmentTypes()
    LoadPatients()
    LoadAppointments()
}

FormatTimeSlot(time24) {
    parts := StrSplit(time24, ":")
    if parts.Length < 2
        return time24
    hour := Integer(parts[1])
    displayHour := hour > 12 ? hour - 12 : (hour = 0 ? 12 : hour)
    return displayHour . ":" . parts[2] . (hour >= 12 ? " PM" : " AM")
}

GetAppointmentKey(date, time) {
    return StrReplace(date, "-", "") . "_" . StrReplace(time, ":", "")
}

GetAppointment(date, time) {
    global g_Appointments
    key := GetAppointmentKey(date, time)
    return g_Appointments.Has(key) && IsObject(g_Appointments[key]) ? g_Appointments[key] : Map()
}

CancelAppointment(date, time) {
    global g_Appointments
    key := GetAppointmentKey(date, time)
    if !g_Appointments.Has(key)
        return false
    g_Appointments.Delete(key)
    SaveAppointments()
    RefreshCalendar()
    ShowStatus("Appointment canceled", "ok")
    return true
}

RefreshCalendarDisplay(*) {
    RefreshCalendar()
}

CalculateNotificationTime(appointmentDateTime, minutesBefore) {
    compact := StrReplace(StrReplace(StrReplace(appointmentDateTime, "-", ""), ":", ""), " ", "")
    if StrLen(compact) = 12
        compact .= "00"
    return FormatTime(DateAdd(compact, -minutesBefore, "Minutes"), "yyyy-MM-dd HH:mm")
}

GetPatient(patientID) {
    global g_Patients
    return g_Patients.Has(patientID) ? g_Patients[patientID] : Map()
}

GetPatientNamesList() {
    return GetPatientNames()
}

GetPatientIDByName(name) {
    global g_Patients
    for id, patient in g_Patients
        if patient["name"] = name
            return id
    return 0
}

OpenBookingDialog(time, existingAppointment := "") {
    global g_CalendarDate, g_AppointmentTypes, MainGui
    bookingGui := Gui("+Owner" . MainGui.Hwnd, "Book Appointment")
    bookingGui.SetFont("s9", "Segoe UI")
    bookingGui.Add("Text", "x12 y12 w370", FormatTime(g_CalendarDate, "dddd, MMMM d, yyyy") . " at " . FormatTimeSlot(time))

    bookingGui.Add("Text", "x12 y48", "Patient:")
    patientNames := GetPatientNamesList()
    if patientNames.Length = 0
        patientNames.Push("(Create a patient first)")
    patientDD := bookingGui.Add("DropDownList", "x95 y45 w220", patientNames)
    patientDD.Choose(1)
    bookingGui.Add("Button", "x322 y44 w65 h24", "New").OnEvent("Click", (*) => OpenNewPatientForBooking(bookingGui, patientDD))

    bookingGui.Add("Text", "x12 y82", "Type:")
    typeNames := []
    for _, typeInfo in g_AppointmentTypes
        typeNames.Push(typeInfo["name"])
    typeDD := bookingGui.Add("DropDownList", "x95 y79 w292", typeNames)
    typeDD.Choose(1)

    bookingGui.Add("Text", "x12 y116", "Scheduled tasks:")
    taskPreview := bookingGui.Add("Edit", "x12 y136 w375 h160 ReadOnly Multi VScroll")
    typeDD.OnEvent("Change", (*) => ShowTaskPreview(typeDD, taskPreview))
    ShowTaskPreview(typeDD, taskPreview)

    if IsObject(existingAppointment) && existingAppointment is Map && existingAppointment.Count > 0 {
        if existingAppointment.Has("patientName")
            patientDD.Text := existingAppointment["patientName"]
        if existingAppointment.Has("typeName")
            typeDD.Text := existingAppointment["typeName"]
    }

    bookingGui.Add("Button", "x95 y310 w100 h30 Default", "Save Booking").OnEvent("Click", (*) => ConfirmAppointmentBooking(time, patientDD, typeDD, bookingGui))
    bookingGui.Add("Button", "x205 y310 w90 h30", "Close").OnEvent("Click", (*) => bookingGui.Destroy())
    bookingGui.Show("w400 h355")
}

OpenNewPatientForBooking(parentGui, patientDD) {
    patientGui := Gui("+Owner" . parentGui.Hwnd, "New Patient")
    patientGui.SetFont("s9", "Segoe UI")
    patientGui.Add("Text", "x10 y12", "Name:")
    nameEdit := patientGui.Add("Edit", "x75 y10 w250")
    patientGui.Add("Text", "x10 y47", "Phone:")
    phoneEdit := patientGui.Add("Edit", "x75 y45 w250")
    patientGui.Add("Text", "x10 y82", "Email:")
    emailEdit := patientGui.Add("Edit", "x75 y80 w250")
    patientGui.Add("Text", "x10 y117", "Notes:")
    notesEdit := patientGui.Add("Edit", "x75 y115 w250 h70 Multi")
    patientGui.Add("Button", "x75 y200 w100 h30 Default", "Create").OnEvent("Click", (*) => SaveNewPatient(nameEdit, phoneEdit, emailEdit, notesEdit, patientGui, patientDD))
    patientGui.Add("Button", "x185 y200 w90 h30", "Cancel").OnEvent("Click", (*) => patientGui.Destroy())
    patientGui.Show("w340 h245")
}

SaveNewPatient(nameEdit, phoneEdit, emailEdit, notesEdit, patientGui, patientDD, *) {
    name := Trim(nameEdit.Value)
    if name = "" {
        MsgBox("Patient name is required.", "New Patient", "Icon!")
        return
    }
    CreatePatient(name, Trim(phoneEdit.Value), Trim(emailEdit.Value), Trim(notesEdit.Value))
    names := GetPatientNamesList()
    patientDD.Delete()
    patientDD.Add(names)
    patientDD.Text := name
    patientGui.Destroy()
    ShowStatus("Patient created: " . name, "ok")
}

ConfirmAppointmentBooking(time, patientDD, typeDD, bookingGui, *) {
    global g_CalendarDate, g_AppointmentTypes
    patientName := patientDD.Text
    patientID := GetPatientIDByName(patientName)
    if !patientID {
        MsgBox("Select or create a patient first.", "Book Appointment", "Icon!")
        return
    }
    appointmentType := ""
    for typeKey, typeInfo in g_AppointmentTypes
        if typeInfo["name"] = typeDD.Text {
            appointmentType := typeKey
            break
        }
    if appointmentType = "" {
        MsgBox("Select an appointment type.", "Book Appointment", "Icon!")
        return
    }
    if BookAppointmentV7(g_CalendarDate, time, patientID, appointmentType) {
        bookingGui.Destroy()
        ShowStatus("Appointment saved for " . patientName . " at " . FormatTimeSlot(time), "ok")
    }
}

BookAppointmentV7(date, time, patientID, appointmentType) {
    global g_Appointments, g_Patients, g_AppointmentTypes
    if !g_Patients.Has(patientID) || !g_AppointmentTypes.Has(appointmentType)
        return false
    patient := g_Patients[patientID]
    typeInfo := g_AppointmentTypes[appointmentType]
    key := GetAppointmentKey(date, time)
    g_Appointments[key] := Map(
        "date", StrReplace(date, "-", ""),
        "time", time,
        "patientID", patientID,
        "patientName", patient["name"],
        "appointmentType", appointmentType,
        "typeName", typeInfo["name"],
        "duration", typeInfo["duration"],
        "tasks", typeInfo["tasks"],
        "status", "Scheduled"
    )

    if !patient.Has("visitHistory")
        patient["visitHistory"] := []
    visitRecorded := false
    for visitDate in patient["visitHistory"]
        if visitDate = StrReplace(date, "-", "")
            visitRecorded := true
    if !visitRecorded
        patient["visitHistory"].Push(StrReplace(date, "-", ""))

    appointmentStamp := StrReplace(date, "-", "") . StrReplace(time, ":", "") . "00"
    for task in typeInfo["tasks"] {
        triggerTime := DateAdd(appointmentStamp, -task["notifyBefore"], "Minutes")
        if DateDiff(triggerTime, A_Now, "Seconds") > 0
            CreateScheduledNotification(triggerTime, "Appointment Task", patient["name"] . " - " . task["task"])
    }
    SaveAppointments()
    SavePatients()
    RefreshCalendar()
    return true
}

OpenPatientList(*) {
    global MainGui
    listGui := Gui("+Owner" . MainGui.Hwnd . " +Resize +MinSize620x350", "Patients")
    listGui.SetFont("s9", "Segoe UI")
    patientLV := listGui.Add("ListView", "x10 y10 w680 h300 Grid", ["ID", "Name", "Phone", "Email", "Last Visit"])
    patientLV.ModifyCol(1, 45)
    patientLV.ModifyCol(2, 175)
    patientLV.ModifyCol(3, 120)
    patientLV.ModifyCol(4, 210)
    patientLV.ModifyCol(5, 100)
    RefreshPatientListLV(patientLV)
    listGui.Add("Button", "x10 y320 w90 h28", "New Patient").OnEvent("Click", (*) => OpenPatientProfileEditor(0))
    listGui.Add("Button", "x110 y320 w90 h28", "Edit").OnEvent("Click", (*) => EditSelectedPatient(patientLV))
    listGui.Add("Button", "x210 y320 w90 h28", "Refresh").OnEvent("Click", (*) => RefreshPatientListLV(patientLV))
    listGui.Add("Button", "x600 y320 w90 h28", "Close").OnEvent("Click", (*) => listGui.Destroy())
    patientLV.OnEvent("DoubleClick", (*) => EditSelectedPatient(patientLV))
    listGui.Show("w700 h365")
}

RefreshPatientListLV(lv) {
    global g_Patients
    lv.Delete()
    for id, patient in g_Patients {
        lastVisit := ""
        if patient.Has("visitHistory") && patient["visitHistory"].Length > 0
            lastVisit := patient["visitHistory"][patient["visitHistory"].Length]
        lv.Add(, id, patient["name"], patient["phone"], patient["email"], lastVisit)
    }
}

EditSelectedPatient(lv) {
    row := lv.GetNext(0, "Focused")
    if row > 0
        OpenPatientProfileEditor(Integer(lv.GetText(row, 1)))
}

GetPatientNames() {
    names := []
    for id, patient in g_Patients {
        names.Push(patient["name"])
    }
    return names
}

