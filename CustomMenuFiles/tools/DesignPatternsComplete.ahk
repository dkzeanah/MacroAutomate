; ╔══════════════════════════════════════════════════════════════════════════════╗
; ║  COMPREHENSIVE AUTOHOTKEY V2 DESIGN PATTERNS DEMONSTRATION                   ║
; ║  Author: Educational Example                                                  ║
; ║  Purpose: Demonstrate ALL Gang of Four patterns plus architectural concepts   ║
; ╚══════════════════════════════════════════════════════════════════════════════╝

; ============================================================================
; IMPORTANT: This file is meant for LEARNING and REFERENCE.
; Each pattern is explained with verbose code and comments.
; Above verbose code, you'll see the "shorter form" as a comment.
; ============================================================================

#Requires AutoHotkey v2.0  ; This directive tells AHK that version 2.0+ is required


; ╔══════════════════════════════════════════════════════════════════════════════╗
; ║  SECTION 1: CREATING CUSTOM TYPES (ENUMERATIONS AND VALUE OBJECTS)           ║
; ╚══════════════════════════════════════════════════════════════════════════════╝

; ==============================================================================
; CUSTOM TYPE: LogLevel (Simulated Enumeration)
; ==============================================================================
; This class acts like an "enum" from other languages.
; It defines a fixed set of named constants that represent logging severity.
; We use this custom type throughout the codebase for type-safe logging.
; ==============================================================================

; SHORT FORM: class LogLevel { static Debug := 1, Info := 2, Warning := 3, Error := 4, Critical := 5 }

class LogLevel {
    ; -------------------------------------------------------------------------
    ; Static properties define the available log levels as named constants.
    ; "static" means these belong to the CLASS itself, not to instances.
    ; We don't create "new LogLevel()" objects - we just use LogLevel.Debug, etc.
    ; -------------------------------------------------------------------------
    
    ; Debug level (1) - Most verbose, for detailed troubleshooting information
    static Debug := 1
    
    ; Info level (2) - General informational messages about normal operation
    static Info := 2
    
    ; Warning level (3) - Something unexpected happened but execution continues
    static Warning := 3
    
    ; Error level (4) - A significant problem occurred that affects functionality
    static Error := 4
    
    ; Critical level (5) - Severe error that may cause program to terminate
    static Critical := 5
    
    ; -------------------------------------------------------------------------
    ; This static method converts a numeric level back to its string name.
    ; It's useful for displaying human-readable log level names in output.
    ; -------------------------------------------------------------------------
    
    ; SHORT FORM: static ToString(level) => ["Debug","Info","Warning","Error","Critical"][level]
    
    static ToString(numericLevelValue) {
        ; Create a Map that associates each numeric value with its string name
        ; A Map is like a dictionary - it stores key-value pairs
        local levelNameLookupMap := Map(
            1, "Debug",      ; Key 1 maps to value "Debug"
            2, "Info",       ; Key 2 maps to value "Info"
            3, "Warning",    ; Key 3 maps to value "Warning"
            4, "Error",      ; Key 4 maps to value "Error"
            5, "Critical"    ; Key 5 maps to value "Critical"
        )
        
        ; The .Get() method retrieves the value for a given key
        ; The second parameter "Unknown" is a default if the key doesn't exist
        local stringNameResult := levelNameLookupMap.Get(numericLevelValue, "Unknown")
        
        ; Return the string name back to whoever called this method
        return stringNameResult
    }
}


; ==============================================================================
; CUSTOM TYPE: UserRole (Another Simulated Enumeration)
; ==============================================================================

; SHORT FORM: class UserRole { static Guest := "guest", User := "user", Admin := "admin", SuperAdmin := "super" }

class UserRole {
    ; Each static property holds a string value representing the role.
    static Guest := "guest"
    static User := "user"
    static Admin := "admin"
    static SuperAdmin := "super_admin"
    
    ; SHORT FORM: static IsValid(r) => (r = "guest" || r = "user" || r = "admin" || r = "super_admin")
    
    static IsValid(roleStringToValidate) {
        ; Create an array containing all valid role strings
        local arrayOfValidRoles := [
            UserRole.Guest,
            UserRole.User,
            UserRole.Admin,
            UserRole.SuperAdmin
        ]
        
        ; Loop through each valid role to check for a match
        for indexNumber, validRoleString in arrayOfValidRoles {
            if (roleStringToValidate = validRoleString) {
                return true
            }
        }
        return false
    }
}


; ==============================================================================
; CUSTOM TYPE: Result (A Value Object for Operation Outcomes)
; ==============================================================================

; SHORT FORM: class Result { __New(ok, val, err) { this.Success := ok, this.Value := val, this.Error := err } }

class Result {
    Success := false
    Value := ""
    Error := ""
    
    ; SHORT FORM: __New(s, v, e) { this.Success := s, this.Value := v, this.Error := e }
    
    __New(isSuccessfulBoolean, resultValueData, errorMessageString) {
        ; "this" refers to the specific instance being created
        this.Success := isSuccessfulBoolean
        this.Value := resultValueData
        this.Error := errorMessageString
    }
    
    ; SHORT FORM: static Ok(v) => Result(true, v, "")
    
    static Ok(successfulValueData) {
        local newSuccessfulResult := Result(true, successfulValueData, "")
        return newSuccessfulResult
    }
    
    ; SHORT FORM: static Fail(e) => Result(false, "", e)
    
    static Fail(errorMessageText) {
        local newFailedResult := Result(false, "", errorMessageText)
        return newFailedResult
    }
}


; ╔══════════════════════════════════════════════════════════════════════════════╗
; ║  SECTION 2: INTERFACES (CONTRACTS FOR DECOUPLED CODE)                        ║
; ╚══════════════════════════════════════════════════════════════════════════════╝

; ==============================================================================
; INTERFACE: ILogger (Contract for Logging Implementations)
; ==============================================================================

; SHORT FORM: class ILogger { Log(m,l) { throw Error("Not implemented") } }

class ILogger {
    Log(messageText, logLevelValue) {
        throw Error("ILogger.Log must be implemented by derived class")
    }
    
    SetMinimumLevel(minimumLogLevelValue) {
        throw Error("ILogger.SetMinimumLevel must be implemented by derived class")
    }
}


; ==============================================================================
; INTERFACE: IRepository (Contract for Data Access)
; ==============================================================================

class IRepository {
    GetById(entityIdValue) {
        throw Error("IRepository.GetById must be implemented by derived class")
    }
    
    GetAll() {
        throw Error("IRepository.GetAll must be implemented by derived class")
    }
    
    Add(entityObject) {
        throw Error("IRepository.Add must be implemented by derived class")
    }
    
    Update(entityObject) {
        throw Error("IRepository.Update must be implemented by derived class")
    }
    
    Delete(entityIdValue) {
        throw Error("IRepository.Delete must be implemented by derived class")
    }
    
    Exists(entityIdValue) {
        throw Error("IRepository.Exists must be implemented by derived class")
    }
}


; ==============================================================================
; INTERFACE: IUserService (Contract for User Business Logic)
; ==============================================================================

class IUserService {
    Authenticate(usernameString, passwordString) {
        throw Error("IUserService.Authenticate must be implemented")
    }
    
    Register(userDataObject) {
        throw Error("IUserService.Register must be implemented")
    }
    
    HasPermission(userIdValue, permissionNameString) {
        throw Error("IUserService.HasPermission must be implemented")
    }
}


; ==============================================================================
; INTERFACE: INotificationService
; ==============================================================================

class INotificationService {
    Send(recipientIdentifier, messageContent) {
        throw Error("INotificationService.Send must be implemented")
    }
    
    SendBulk(arrayOfRecipients, messageContent) {
        throw Error("INotificationService.SendBulk must be implemented")
    }
}


; ╔══════════════════════════════════════════════════════════════════════════════╗
; ║  SECTION 3: DOMAIN ENTITIES (Business Objects)                               ║
; ╚══════════════════════════════════════════════════════════════════════════════╝

; ==============================================================================
; ENTITY: User
; ==============================================================================

; SHORT FORM: class User { __New(id,name,email,role) { this.Id:=id, this.Name:=name, ... } }

class User {
    Id := 0
    Name := ""
    Email := ""
    Role := UserRole.Guest
    CreatedAt := ""
    LastLoginAt := ""
    IsActive := true
    
    __New(userIdValue, userNameString, userEmailString, userRoleValue) {
        this.Id := userIdValue
        this.Name := userNameString
        this.Email := userEmailString
        this.Role := userRoleValue
        this.CreatedAt := A_Now
        this.LastLoginAt := ""
        this.IsActive := true
    }
    
    ; SHORT FORM: Validate() => (this.Name && this.Email) ? Result.Ok(true) : Result.Fail("Invalid")
    
    Validate() {
        local arrayOfValidationErrors := []
        
        if (StrLen(this.Name) < 2) {
            arrayOfValidationErrors.Push("Name must be at least 2 characters")
        }
        
        if (!InStr(this.Email, "@")) {
            arrayOfValidationErrors.Push("Email must contain @ symbol")
        }
        
        if (!UserRole.IsValid(this.Role)) {
            arrayOfValidationErrors.Push("Role must be a valid UserRole value")
        }
        
        if (arrayOfValidationErrors.Length > 0) {
            local combinedErrorString := ""
            for indexNumber, errorMessage in arrayOfValidationErrors {
                if (combinedErrorString != "") {
                    combinedErrorString := combinedErrorString . ", "
                }
                combinedErrorString := combinedErrorString . errorMessage
            }
            return Result.Fail(combinedErrorString)
        }
        
        return Result.Ok(true)
    }
    
    RecordLogin() {
        this.LastLoginAt := A_Now
    }
    
    ; SHORT FORM: ToString() => "User(" . this.Id . ":" . this.Name . ")"
    
    ToString() {
        local stringRepresentation := "User("
        stringRepresentation := stringRepresentation . "Id=" . this.Id
        stringRepresentation := stringRepresentation . ", Name=" . this.Name
        stringRepresentation := stringRepresentation . ", Email=" . this.Email
        stringRepresentation := stringRepresentation . ", Role=" . this.Role
        stringRepresentation := stringRepresentation . ", Active=" . (this.IsActive ? "Yes" : "No")
        stringRepresentation := stringRepresentation . ")"
        return stringRepresentation
    }
}


; ╔══════════════════════════════════════════════════════════════════════════════╗
; ║  SECTION 4: GANG OF FOUR - CREATIONAL PATTERNS                               ║
; ╚══════════════════════════════════════════════════════════════════════════════╝


; ==============================================================================
; PATTERN 1: SINGLETON
; ==============================================================================
; Purpose: Ensure a class has only ONE instance and provide global access point.
; Use when: You need exactly one object to coordinate actions across the system.
; ==============================================================================

; SHORT FORM: class ConfigManager { static _inst := "", static Instance { get => this._inst || (this._inst := ConfigManager()) } }

class ConfigurationManagerSingleton {
    static _singletonInstanceStorage := ""
    
    ; SHORT FORM: static Instance { get => this._singletonInstanceStorage || (this._singletonInstanceStorage := ConfigurationManagerSingleton()) }
    
    static Instance {
        get {
            if (ConfigurationManagerSingleton._singletonInstanceStorage = "") {
                ConfigurationManagerSingleton._singletonInstanceStorage := ConfigurationManagerSingleton()
            }
            return ConfigurationManagerSingleton._singletonInstanceStorage
        }
    }
    
    _configurationDataMap := Map()
    
    __New() {
        this._configurationDataMap.Set("ApplicationName", "Design Patterns Demo")
        this._configurationDataMap.Set("Version", "1.0.0")
        this._configurationDataMap.Set("DebugMode", false)
        this._configurationDataMap.Set("MaxConnections", 100)
    }
    
    ; SHORT FORM: Get(k, d := "") => this._configurationDataMap.Get(k, d)
    
    GetConfigurationValue(configurationKeyString, defaultValueIfNotFound := "") {
        local retrievedValue := this._configurationDataMap.Get(
            configurationKeyString,
            defaultValueIfNotFound
        )
        return retrievedValue
    }
    
    SetConfigurationValue(configurationKeyString, newConfigurationValue) {
        this._configurationDataMap.Set(configurationKeyString, newConfigurationValue)
    }
}


; ==============================================================================
; PATTERN 2: FACTORY METHOD
; ==============================================================================
; Purpose: Define an interface for creating an object, but let subclasses decide.
; ==============================================================================

; SHORT FORM: class DocumentCreator { CreateDocument() { throw Error("Abstract") } }

class DocumentCreatorBase {
    CreateDocument() {
        throw Error("DocumentCreatorBase.CreateDocument is abstract")
    }
    
    RenderDocument() {
        local createdDocumentObject := this.CreateDocument()
        createdDocumentObject.Render()
        return createdDocumentObject
    }
}

class PdfDocument {
    Content := ""
    Render() {
        this.Content := "Rendered as PDF format"
        return this.Content
    }
    GetFileExtension() {
        return ".pdf"
    }
}

class HtmlDocument {
    Content := ""
    Render() {
        this.Content := "<html><body>Rendered as HTML</body></html>"
        return this.Content
    }
    GetFileExtension() {
        return ".html"
    }
}

; SHORT FORM: class PdfCreator extends DocumentCreatorBase { CreateDocument() => PdfDocument() }

class PdfDocumentCreator extends DocumentCreatorBase {
    CreateDocument() {
        local newPdfDocument := PdfDocument()
        return newPdfDocument
    }
}

class HtmlDocumentCreator extends DocumentCreatorBase {
    CreateDocument() {
        local newHtmlDocument := HtmlDocument()
        return newHtmlDocument
    }
}


; ==============================================================================
; PATTERN 3: ABSTRACT FACTORY
; ==============================================================================
; Purpose: Create FAMILIES of related objects without specifying concrete classes.
; ==============================================================================

class IUserInterfaceFactory {
    CreateButton() {
        throw Error("Must implement CreateButton")
    }
    CreateTextBox() {
        throw Error("Must implement CreateTextBox")
    }
}

class WindowsButton {
    _labelText := ""
    __New(labelText := "Button") {
        this._labelText := labelText
    }
    Render() {
        return "[Windows Button: " . this._labelText . "]"
    }
}

class MacButton {
    _labelText := ""
    __New(labelText := "Button") {
        this._labelText := labelText
    }
    Render() {
        return "( Mac Button: " . this._labelText . " )"
    }
}

class WindowsUserInterfaceFactory extends IUserInterfaceFactory {
    CreateButton() {
        return WindowsButton()
    }
    CreateTextBox() {
        return {Render: () => "|Windows TextBox|"}
    }
}

class MacUserInterfaceFactory extends IUserInterfaceFactory {
    CreateButton() {
        return MacButton()
    }
    CreateTextBox() {
        return {Render: () => "[ Mac TextBox ]"}
    }
}


; ==============================================================================
; PATTERN 4: BUILDER
; ==============================================================================
; Purpose: Separate construction of complex objects from their representation.
; ==============================================================================

class EmailMessage {
    RecipientAddress := ""
    SenderAddress := ""
    SubjectLine := ""
    BodyContent := ""
    ArrayOfCcRecipients := []
    ArrayOfAttachments := []
    IsHighPriority := false
}

; SHORT FORM: class EmailBuilder { _e := EmailMessage(), To(v) { this._e.RecipientAddress := v, return this } ... Build() => this._e }

class EmailMessageBuilder {
    _emailBeingBuilt := ""
    
    __New() {
        this._emailBeingBuilt := EmailMessage()
    }
    
    ; Each setter returns "this" for method chaining (fluent interface)
    
    SetRecipient(recipientEmailAddress) {
        this._emailBeingBuilt.RecipientAddress := recipientEmailAddress
        return this
    }
    
    SetSender(senderEmailAddress) {
        this._emailBeingBuilt.SenderAddress := senderEmailAddress
        return this
    }
    
    SetSubject(subjectLineText) {
        this._emailBeingBuilt.SubjectLine := subjectLineText
        return this
    }
    
    SetBody(bodyContentText) {
        this._emailBeingBuilt.BodyContent := bodyContentText
        return this
    }
    
    SetHighPriority(isHighPriorityBoolean := true) {
        this._emailBeingBuilt.IsHighPriority := isHighPriorityBoolean
        return this
    }
    
    Build() {
        local finishedEmail := this._emailBeingBuilt
        this._emailBeingBuilt := EmailMessage()
        return finishedEmail
    }
}


; ==============================================================================
; PATTERN 5: PROTOTYPE
; ==============================================================================
; Purpose: Create new objects by copying existing ones.
; ==============================================================================

class ShapePrototype {
    XPosition := 0
    YPosition := 0
    WidthValue := 100
    HeightValue := 100
    ColorValue := "Black"
    ShapeType := "Rectangle"
    
    ; SHORT FORM: Clone() { s := ShapePrototype(), s.XPosition := this.XPosition, ... return s }
    
    Clone() {
        local clonedShapeObject := ShapePrototype()
        clonedShapeObject.XPosition := this.XPosition
        clonedShapeObject.YPosition := this.YPosition
        clonedShapeObject.WidthValue := this.WidthValue
        clonedShapeObject.HeightValue := this.HeightValue
        clonedShapeObject.ColorValue := this.ColorValue
        clonedShapeObject.ShapeType := this.ShapeType
        return clonedShapeObject
    }
    
    ToString() {
        return this.ShapeType . " at (" . this.XPosition . "," . this.YPosition . ") - " . this.ColorValue
    }
}


; ╔══════════════════════════════════════════════════════════════════════════════╗
; ║  SECTION 5: GANG OF FOUR - STRUCTURAL PATTERNS                               ║
; ╚══════════════════════════════════════════════════════════════════════════════╝


; ==============================================================================
; PATTERN 6: ADAPTER
; ==============================================================================
; Purpose: Convert the interface of a class into another interface clients expect.
; ==============================================================================

class IModernLogger {
    LogMessage(messageText, severityLevel) {
        throw Error("Must implement LogMessage")
    }
}

class LegacyLoggingSystem {
    WriteToLogFile(logTypeCode, messageContent, timestampValue) {
        local formattedEntry := "[" . timestampValue . "] " . logTypeCode . ": " . messageContent
        return formattedEntry
    }
}

; SHORT FORM: class LoggerAdapter extends IModernLogger { __New(l) { this._legacy := l }, LogMessage(m, s) { this._legacy.WriteToLogFile(...) } }

class LegacyLoggerAdapter extends IModernLogger {
    _legacyLoggerReference := ""
    
    __New(legacyLoggerInstance) {
        this._legacyLoggerReference := legacyLoggerInstance
    }
    
    LogMessage(messageText, severityLevel) {
        local legacyTypeCode := this._ConvertSeverityToLegacyCode(severityLevel)
        local currentTimestamp := A_Now
        return this._legacyLoggerReference.WriteToLogFile(
            legacyTypeCode,
            messageText,
            currentTimestamp
        )
    }
    
    _ConvertSeverityToLegacyCode(modernSeverityLevel) {
        if (modernSeverityLevel >= LogLevel.Error) {
            return "ERR"
        } else if (modernSeverityLevel >= LogLevel.Warning) {
            return "WRN"
        } else {
            return "INF"
        }
    }
}


; ==============================================================================
; PATTERN 7: BRIDGE
; ==============================================================================
; Purpose: Decouple abstraction from implementation.
; ==============================================================================

class IMessageSenderImplementor {
    SendRawMessage(rawMessageData) {
        throw Error("Must implement SendRawMessage")
    }
}

class EmailMessageSenderImplementor extends IMessageSenderImplementor {
    _smtpServerAddress := ""
    
    __New(smtpServer := "smtp.example.com") {
        this._smtpServerAddress := smtpServer
    }
    
    SendRawMessage(rawMessageData) {
        return "EMAIL via " . this._smtpServerAddress . ": " . rawMessageData
    }
}

class SmsMessageSenderImplementor extends IMessageSenderImplementor {
    _smsGatewayUrl := ""
    
    __New(gatewayUrl := "https://sms.example.com") {
        this._smsGatewayUrl := gatewayUrl
    }
    
    SendRawMessage(rawMessageData) {
        return "SMS via " . this._smsGatewayUrl . ": " . rawMessageData
    }
}

; SHORT FORM: class Message { __New(impl) { this._impl := impl }, Send() { this._impl.SendRawMessage(this._Format()) } }

class MessageAbstraction {
    _messageImplementorReference := ""
    _recipientValue := ""
    _contentText := ""
    
    __New(implementorInstance) {
        this._messageImplementorReference := implementorInstance
    }
    
    SetRecipient(recipientIdentifier) {
        this._recipientValue := recipientIdentifier
        return this
    }
    
    SetContent(contentText) {
        this._contentText := contentText
        return this
    }
    
    Send() {
        local formattedMessage := this._FormatMessage()
        return this._messageImplementorReference.SendRawMessage(formattedMessage)
    }
    
    _FormatMessage() {
        return "To: " . this._recipientValue . " | Message: " . this._contentText
    }
}


; ==============================================================================
; PATTERN 8: COMPOSITE
; ==============================================================================
; Purpose: Compose objects into tree structures to represent hierarchies.
; ==============================================================================

class FileComponent {
    _fileName := ""
    _fileSizeInBytes := 0
    
    __New(nameString, sizeInBytes) {
        this._fileName := nameString
        this._fileSizeInBytes := sizeInBytes
    }
    
    GetName() {
        return this._fileName
    }
    
    GetSize() {
        return this._fileSizeInBytes
    }
    
    Display(indentationLevel := 0) {
        local indentString := ""
        local loopCounter := 0
        while (loopCounter < indentationLevel) {
            indentString := indentString . "  "
            loopCounter := loopCounter + 1
        }
        return indentString . "📄 " . this.GetName() . " (" . this._fileSizeInBytes . " bytes)"
    }
}

; SHORT FORM: class Folder { Add(c) { this._children.Push(c) }, GetSize() { ... loop children ... } }

class FolderComponent {
    _folderName := ""
    _arrayOfChildren := []
    
    __New(nameString) {
        this._folderName := nameString
        this._arrayOfChildren := []
    }
    
    AddChild(childComponent) {
        this._arrayOfChildren.Push(childComponent)
        return this
    }
    
    GetName() {
        return this._folderName
    }
    
    ; SHORT FORM: GetSize() { t := 0, for c in this._arrayOfChildren { t += c.GetSize() }, return t }
    
    GetSize() {
        local totalSizeAccumulator := 0
        for indexNumber, childComponent in this._arrayOfChildren {
            local childSize := childComponent.GetSize()
            totalSizeAccumulator := totalSizeAccumulator + childSize
        }
        return totalSizeAccumulator
    }
    
    Display(indentationLevel := 0) {
        local indentString := ""
        local loopCounter := 0
        while (loopCounter < indentationLevel) {
            indentString := indentString . "  "
            loopCounter := loopCounter + 1
        }
        
        local outputString := indentString . "📁 " . this._folderName . "/ (" . this.GetSize() . " bytes)`n"
        
        for indexNumber, childComponent in this._arrayOfChildren {
            outputString := outputString . childComponent.Display(indentationLevel + 1) . "`n"
        }
        
        return outputString
    }
}


; ==============================================================================
; PATTERN 9: DECORATOR
; ==============================================================================
; Purpose: Attach additional responsibilities to an object dynamically.
; ==============================================================================

class PlainTextComponent {
    _rawTextContent := ""
    
    __New(textContent) {
        this._rawTextContent := textContent
    }
    
    GetContent() {
        return this._rawTextContent
    }
}

; SHORT FORM: class TextDecorator { __New(c) { this._wrapped := c }, GetContent() => this._wrapped.GetContent() }

class TextDecoratorBase {
    _wrappedComponent := ""
    
    __New(componentToWrap) {
        this._wrappedComponent := componentToWrap
    }
    
    GetContent() {
        return this._wrappedComponent.GetContent()
    }
}

; SHORT FORM: class BoldDecorator extends TextDecoratorBase { GetContent() => "**" . this._wrappedComponent.GetContent() . "**" }

class BoldTextDecorator extends TextDecoratorBase {
    GetContent() {
        local originalContent := this._wrappedComponent.GetContent()
        local boldContent := "**" . originalContent . "**"
        return boldContent
    }
}

class ItalicTextDecorator extends TextDecoratorBase {
    GetContent() {
        local originalContent := this._wrappedComponent.GetContent()
        local italicContent := "_" . originalContent . "_"
        return italicContent
    }
}

class UppercaseTextDecorator extends TextDecoratorBase {
    GetContent() {
        local originalContent := this._wrappedComponent.GetContent()
        local uppercasedContent := StrUpper(originalContent)
        return uppercasedContent
    }
}


; ==============================================================================
; PATTERN 10: FACADE
; ==============================================================================
; Purpose: Provide a unified interface to a set of interfaces in a subsystem.
; ==============================================================================

class VideoFileReader {
    _filePath := ""
    Open(filePath) {
        this._filePath := filePath
        return "Opened: " . filePath
    }
    ReadFrame(frameNumber) {
        return "Read frame " . frameNumber
    }
    Close() {
        return "Closed: " . this._filePath
    }
}

class VideoEncoder {
    _codecType := ""
    SetCodec(codecName) {
        this._codecType := codecName
        return "Codec: " . codecName
    }
    Encode(frameData) {
        return "Encoded with " . this._codecType
    }
}

; SHORT FORM: class VideoConverterFacade { Convert(in, out, fmt) { ... all steps hidden ... } }

class VideoConverterFacade {
    _videoReader := ""
    _videoEncoder := ""
    
    __New() {
        this._videoReader := VideoFileReader()
        this._videoEncoder := VideoEncoder()
    }
    
    ConvertVideo(inputFilePath, outputFilePath, targetFormat) {
        ; The facade hides all the complexity
        this._videoReader.Open(inputFilePath)
        this._videoEncoder.SetCodec(targetFormat = "mp4" ? "H.264" : "VP9")
        this._videoEncoder.Encode("frame_data")
        this._videoReader.Close()
        
        return "Converted " . inputFilePath . " to " . outputFilePath
    }
}


; ==============================================================================
; PATTERN 11: FLYWEIGHT
; ==============================================================================
; Purpose: Use sharing to support large numbers of fine-grained objects.
; ==============================================================================

class CharacterGlyphFlyweight {
    CharacterValue := ""
    FontFamily := ""
    FontSize := 0
    
    __New(characterValue, fontFamilyName, fontSizePoints) {
        this.CharacterValue := characterValue
        this.FontFamily := fontFamilyName
        this.FontSize := fontSizePoints
    }
    
    ; SHORT FORM: Render(x, y) => "'" . this.CharacterValue . "' at (" . x . "," . y . ")"
    
    Render(xPosition, yPosition, colorValue) {
        return "'" . this.CharacterValue . "' at (" . xPosition . "," . yPosition . ") " . this.FontFamily . " " . this.FontSize . "pt " . colorValue
    }
}

; SHORT FORM: class GlyphFactory { static _p := Map(), static Get(c, f, s) { k := c.f.s, return this._p.Has(k) ? this._p[k] : (this._p[k] := CharacterGlyphFlyweight(c,f,s)) } }

class CharacterGlyphFactory {
    static _flyweightPoolMap := Map()
    static _totalRequestCount := 0
    static _actualCreationCount := 0
    
    static GetGlyph(characterValue, fontFamilyName, fontSizePoints) {
        CharacterGlyphFactory._totalRequestCount += 1
        
        local flyweightKey := characterValue . "|" . fontFamilyName . "|" . fontSizePoints
        
        if (!CharacterGlyphFactory._flyweightPoolMap.Has(flyweightKey)) {
            local newFlyweight := CharacterGlyphFlyweight(characterValue, fontFamilyName, fontSizePoints)
            CharacterGlyphFactory._flyweightPoolMap.Set(flyweightKey, newFlyweight)
            CharacterGlyphFactory._actualCreationCount += 1
        }
        
        return CharacterGlyphFactory._flyweightPoolMap.Get(flyweightKey)
    }
    
    static GetStatistics() {
        return "Requests: " . CharacterGlyphFactory._totalRequestCount . ", Created: " . CharacterGlyphFactory._actualCreationCount
    }
}


; ==============================================================================
; PATTERN 12: PROXY
; ==============================================================================
; Purpose: Provide a surrogate to control access to an object.
; ==============================================================================

class ExpensiveDatabaseConnection {
    _connectionString := ""
    _loadedData := ""
    
    __New(connectionString) {
        this._connectionString := connectionString
        ; Simulates expensive connection
    }
    
    LoadData() {
        this._loadedData := "Data from: " . this._connectionString
        return this._loadedData
    }
    
    GetData() {
        if (this._loadedData = "") {
            this.LoadData()
        }
        return this._loadedData
    }
}

; SHORT FORM: class DatabaseProxy { GetData() { if !this._real { this._real := ExpensiveDatabaseConnection(...) }, return this._real.GetData() } }

class VirtualDatabaseProxy {
    _realDatabaseReference := ""
    _connectionStringStored := ""
    
    __New(connectionString) {
        ; Just store - don't create the expensive object yet
        this._connectionStringStored := connectionString
    }
    
    _EnsureRealObjectExists() {
        if (this._realDatabaseReference = "") {
            ; Lazy initialization - created only when needed
            this._realDatabaseReference := ExpensiveDatabaseConnection(this._connectionStringStored)
        }
    }
    
    GetData() {
        this._EnsureRealObjectExists()
        return this._realDatabaseReference.GetData()
    }
    
    IsRealObjectCreated() {
        return (this._realDatabaseReference != "")
    }
}


; ╔══════════════════════════════════════════════════════════════════════════════╗
; ║  SECTION 6: GANG OF FOUR - BEHAVIORAL PATTERNS                               ║
; ╚══════════════════════════════════════════════════════════════════════════════╝


; ==============================================================================
; PATTERN 13: CHAIN OF RESPONSIBILITY
; ==============================================================================
; Purpose: Pass requests along a chain of handlers.
; ==============================================================================

; SHORT FORM: class SupportHandler { SetNext(n) { this._next := n, return n }, Handle(r) { return this._next ? this._next.Handle(r) : "" } }

class SupportHandlerBase {
    _nextHandlerInChain := ""
    
    SetNext(nextHandler) {
        this._nextHandlerInChain := nextHandler
        return nextHandler
    }
    
    Handle(requestObject) {
        if (this._nextHandlerInChain != "") {
            return this._nextHandlerInChain.Handle(requestObject)
        }
        return ""
    }
}

class SupportTicket {
    IssueType := ""
    Severity := ""
    Description := ""
    
    __New(issueType, severity, description) {
        this.IssueType := issueType
        this.Severity := severity
        this.Description := description
    }
}

class TechnicalSupportHandler extends SupportHandlerBase {
    Handle(requestTicket) {
        local canHandleThis := (requestTicket.IssueType = "technical")
        
        if (canHandleThis) {
            return "TECH SUPPORT: Resolved - " . requestTicket.Description
        }
        return super.Handle(requestTicket)
    }
}

class BillingSupportHandler extends SupportHandlerBase {
    Handle(requestTicket) {
        local canHandleThis := (requestTicket.IssueType = "billing")
        
        if (canHandleThis) {
            return "BILLING: Resolved - " . requestTicket.Description
        }
        return super.Handle(requestTicket)
    }
}


; ==============================================================================
; PATTERN 14: COMMAND
; ==============================================================================
; Purpose: Encapsulate a request as an object, enabling undo.
; ==============================================================================

class TextEditorReceiver {
    _textContent := ""
    _cursorPosition := 0
    
    GetText() {
        return this._textContent
    }
    
    InsertText(textToInsert) {
        local beforeCursor := SubStr(this._textContent, 1, this._cursorPosition)
        local afterCursor := SubStr(this._textContent, this._cursorPosition + 1)
        this._textContent := beforeCursor . textToInsert . afterCursor
        this._cursorPosition := this._cursorPosition + StrLen(textToInsert)
    }
    
    DeleteCharacters(numberOfCharacters) {
        if (this._cursorPosition >= numberOfCharacters) {
            local beforeDeletion := SubStr(this._textContent, 1, this._cursorPosition - numberOfCharacters)
            local afterCursor := SubStr(this._textContent, this._cursorPosition + 1)
            this._textContent := beforeDeletion . afterCursor
            this._cursorPosition := this._cursorPosition - numberOfCharacters
        }
    }
    
    GetCursorPosition() {
        return this._cursorPosition
    }
}

; SHORT FORM: class InsertCommand { Execute() { this._editor.InsertText(this._text) }, Undo() { this._editor.DeleteCharacters(StrLen(this._text)) } }

class InsertTextCommand {
    _editorReceiver := ""
    _textToInsert := ""
    
    __New(editorReceiver, textToInsert) {
        this._editorReceiver := editorReceiver
        this._textToInsert := textToInsert
    }
    
    Execute() {
        this._editorReceiver.InsertText(this._textToInsert)
        return "Inserted: '" . this._textToInsert . "'"
    }
    
    Undo() {
        this._editorReceiver.DeleteCharacters(StrLen(this._textToInsert))
        return "Undid insert of: '" . this._textToInsert . "'"
    }
    
    GetDescription() {
        return "Insert '" . this._textToInsert . "'"
    }
}

; SHORT FORM: class CommandInvoker { _history := [], Execute(c) { c.Execute(), this._history.Push(c) }, Undo() { c := this._history.Pop(), c.Undo() } }

class CommandInvoker {
    _commandHistoryArray := []
    _redoStackArray := []
    
    ExecuteCommand(commandToExecute) {
        local result := commandToExecute.Execute()
        this._commandHistoryArray.Push(commandToExecute)
        this._redoStackArray := []
        return result
    }
    
    Undo() {
        if (this._commandHistoryArray.Length = 0) {
            return "Nothing to undo"
        }
        local commandToUndo := this._commandHistoryArray.Pop()
        local result := commandToUndo.Undo()
        this._redoStackArray.Push(commandToUndo)
        return result
    }
    
    Redo() {
        if (this._redoStackArray.Length = 0) {
            return "Nothing to redo"
        }
        local commandToRedo := this._redoStackArray.Pop()
        local result := commandToRedo.Execute()
        this._commandHistoryArray.Push(commandToRedo)
        return result
    }
}


; ==============================================================================
; PATTERN 15: INTERPRETER
; ==============================================================================
; Purpose: Define a grammar and interpret expressions.
; ==============================================================================

; SHORT FORM: class NumberExpr { __New(n) { this._n := n }, Interpret(c) => this._n }

class NumberExpression {
    _numericValue := 0
    
    __New(numericValue) {
        this._numericValue := numericValue
    }
    
    Interpret(contextVariablesMap) {
        return this._numericValue
    }
}

; SHORT FORM: class AddExpr { Interpret(c) => this._left.Interpret(c) + this._right.Interpret(c) }

class AdditionExpression {
    _leftOperand := ""
    _rightOperand := ""
    
    __New(leftExpression, rightExpression) {
        this._leftOperand := leftExpression
        this._rightOperand := rightExpression
    }
    
    Interpret(contextVariablesMap) {
        local leftValue := this._leftOperand.Interpret(contextVariablesMap)
        local rightValue := this._rightOperand.Interpret(contextVariablesMap)
        return leftValue + rightValue
    }
}


; ==============================================================================
; PATTERN 16: ITERATOR
; ==============================================================================
; Purpose: Access elements sequentially without exposing structure.
; ==============================================================================

; SHORT FORM: class BookCollection { CreateIterator() => BookIterator(this) }

class BookCollection {
    _booksArray := []
    
    AddBook(bookTitle, bookAuthor) {
        local bookObject := {Title: bookTitle, Author: bookAuthor}
        this._booksArray.Push(bookObject)
    }
    
    GetBookAt(indexNumber) {
        if (indexNumber >= 1 && indexNumber <= this._booksArray.Length) {
            return this._booksArray[indexNumber]
        }
        return ""
    }
    
    GetCount() {
        return this._booksArray.Length
    }
    
    CreateIterator() {
        return BookCollectionIterator(this)
    }
}

; SHORT FORM: class BookIterator { HasNext() => this._pos <= this._coll.GetCount(), Next() { return this._coll.GetBookAt(this._pos++) } }

class BookCollectionIterator {
    _collectionReference := ""
    _currentPosition := 1
    
    __New(bookCollection) {
        this._collectionReference := bookCollection
        this._currentPosition := 1
    }
    
    HasNext() {
        return (this._currentPosition <= this._collectionReference.GetCount())
    }
    
    Next() {
        if (!this.HasNext()) {
            throw Error("No more elements")
        }
        local currentBook := this._collectionReference.GetBookAt(this._currentPosition)
        this._currentPosition := this._currentPosition + 1
        return currentBook
    }
    
    Reset() {
        this._currentPosition := 1
    }
}


; ==============================================================================
; PATTERN 17: MEDIATOR
; ==============================================================================
; Purpose: Define how objects interact without direct references.
; ==============================================================================

; SHORT FORM: class ChatRoom { SendMessage(m, s) { for p in this._participants { if p != s { p.Receive(m, s.Name) } } } }

class ChatRoomMediator {
    _participantsArray := []
    _messageHistoryArray := []
    
    AddParticipant(participantComponent) {
        this._participantsArray.Push(participantComponent)
        participantComponent.SetMediator(this)
    }
    
    SendMessage(messageText, senderComponent) {
        local logEntry := {
            Sender: senderComponent.GetName(),
            Message: messageText
        }
        this._messageHistoryArray.Push(logEntry)
        
        for indexNumber, participantComponent in this._participantsArray {
            if (participantComponent != senderComponent) {
                participantComponent.Receive(messageText, senderComponent.GetName())
            }
        }
    }
}

; SHORT FORM: class ChatUser { Send(m) { this._mediator.SendMessage(m, this) } }

class ChatUserParticipant {
    _userName := ""
    _mediatorReference := ""
    _receivedMessagesArray := []
    
    __New(userName) {
        this._userName := userName
        this._receivedMessagesArray := []
    }
    
    SetMediator(mediatorInstance) {
        this._mediatorReference := mediatorInstance
    }
    
    GetName() {
        return this._userName
    }
    
    Send(messageText) {
        this._mediatorReference.SendMessage(messageText, this)
    }
    
    Receive(messageText, senderName) {
        this._receivedMessagesArray.Push({From: senderName, Message: messageText})
    }
    
    GetReceivedMessages() {
        return this._receivedMessagesArray
    }
}


; ==============================================================================
; PATTERN 18: MEMENTO
; ==============================================================================
; Purpose: Capture and restore object state without exposing internals.
; ==============================================================================

; SHORT FORM: class GameMemento { __New(s) { this._state := s }, GetState() => this._state }

class GameStateMemento {
    _savedPlayerName := ""
    _savedLevel := 0
    _savedScore := 0
    _savedHealth := 0
    
    __New(playerName, level, score, health) {
        this._savedPlayerName := playerName
        this._savedLevel := level
        this._savedScore := score
        this._savedHealth := health
    }
    
    GetPlayerName() { return this._savedPlayerName }
    GetLevel() { return this._savedLevel }
    GetScore() { return this._savedScore }
    GetHealth() { return this._savedHealth }
    
    GetDescription() {
        return "Level " . this._savedLevel . " - Score: " . this._savedScore
    }
}

; SHORT FORM: class Game { Save() => GameMemento(this._p, this._l, this._s, this._h), Restore(m) { this._p := m.GetPlayerName(), ... } }

class GameOriginator {
    _playerName := ""
    _currentLevel := 1
    _currentScore := 0
    _currentHealth := 100
    
    __New(playerName) {
        this._playerName := playerName
    }
    
    LevelUp() {
        this._currentLevel += 1
        this._currentScore += 100
    }
    
    TakeDamage(damageAmount) {
        this._currentHealth := this._currentHealth - damageAmount
        if (this._currentHealth < 0) {
            this._currentHealth := 0
        }
    }
    
    SaveState() {
        return GameStateMemento(
            this._playerName,
            this._currentLevel,
            this._currentScore,
            this._currentHealth
        )
    }
    
    RestoreState(mementoToRestore) {
        this._playerName := mementoToRestore.GetPlayerName()
        this._currentLevel := mementoToRestore.GetLevel()
        this._currentScore := mementoToRestore.GetScore()
        this._currentHealth := mementoToRestore.GetHealth()
    }
    
    GetStateDescription() {
        return "Player: " . this._playerName . " | Level: " . this._currentLevel . " | Score: " . this._currentScore . " | Health: " . this._currentHealth
    }
}


; ==============================================================================
; PATTERN 19: OBSERVER
; ==============================================================================
; Purpose: Notify objects when another object changes.
; ==============================================================================

; SHORT FORM: class Stock { Attach(o) { this._obs.Push(o) }, Notify(d) { for o in this._obs { o.Update(this, d) } } }

class StockPriceSubject {
    _stockSymbol := ""
    _currentPrice := 0.0
    _previousPrice := 0.0
    _observersArray := []
    
    __New(stockSymbol, initialPrice) {
        this._stockSymbol := stockSymbol
        this._currentPrice := initialPrice
        this._previousPrice := initialPrice
        this._observersArray := []
    }
    
    Attach(observerInstance) {
        this._observersArray.Push(observerInstance)
    }
    
    Detach(observerInstance) {
        local newObserversArray := []
        for indexNumber, existingObserver in this._observersArray {
            if (existingObserver != observerInstance) {
                newObserversArray.Push(existingObserver)
            }
        }
        this._observersArray := newObserversArray
    }
    
    Notify(eventData) {
        for indexNumber, observerInstance in this._observersArray {
            observerInstance.Update(this, eventData)
        }
    }
    
    SetPrice(newPrice) {
        this._previousPrice := this._currentPrice
        this._currentPrice := newPrice
        
        local priceChange := newPrice - this._previousPrice
        local percentChange := (priceChange / this._previousPrice) * 100
        
        local eventData := {
            Symbol: this._stockSymbol,
            OldPrice: this._previousPrice,
            NewPrice: newPrice,
            Change: priceChange,
            PercentChange: percentChange
        }
        
        this.Notify(eventData)
    }
    
    GetSymbol() { return this._stockSymbol }
    GetPrice() { return this._currentPrice }
}

; SHORT FORM: class PriceDisplay { Update(s, d) { this._lastUpdate := d } }

class PriceDisplayObserver {
    _displayName := ""
    _lastUpdateData := ""
    
    __New(displayName) {
        this._displayName := displayName
    }
    
    Update(subjectReference, eventData) {
        this._lastUpdateData := eventData
    }
    
    GetLastDisplay() {
        if (this._lastUpdateData = "") {
            return this._displayName . ": No data yet"
        }
        local changeIndicator := this._lastUpdateData.Change >= 0 ? "▲" : "▼"
        return this._displayName . ": " . this._lastUpdateData.Symbol . " $" . Format("{:.2f}", this._lastUpdateData.NewPrice) . " " . changeIndicator . " " . Format("{:.2f}", this._lastUpdateData.PercentChange) . "%"
    }
}

class AlertObserver {
    _thresholdPercent := 0
    _alertsArray := []
    
    __New(thresholdPercent) {
        this._thresholdPercent := thresholdPercent
        this._alertsArray := []
    }
    
    Update(subjectReference, eventData) {
        local absoluteChange := Abs(eventData.PercentChange)
        if (absoluteChange >= this._thresholdPercent) {
            local alertMessage := "ALERT: " . eventData.Symbol . " moved " . Format("{:.2f}", eventData.PercentChange) . "%"
            this._alertsArray.Push(alertMessage)
        }
    }
    
    GetAlerts() {
        return this._alertsArray
    }
}


; ==============================================================================
; PATTERN 20: STATE
; ==============================================================================
; Purpose: Allow an object to alter behavior when its internal state changes.
; ==============================================================================

; SHORT FORM: class PendingState { HandlePayment(ctx) { ctx.SetState(PaidState()), return "Payment processed" } }

class PendingPaymentState {
    HandlePayment(orderContext) {
        orderContext.SetState(PaidState())
        return "Payment processed. Order is now paid."
    }
    HandleShip(orderContext) {
        return "Cannot ship: Not paid yet."
    }
    HandleDeliver(orderContext) {
        return "Cannot deliver: Not shipped yet."
    }
    HandleCancel(orderContext) {
        orderContext.SetState(CancelledState())
        return "Order cancelled."
    }
    GetStateName() {
        return "Pending Payment"
    }
}

class PaidState {
    HandlePayment(orderContext) {
        return "Already paid."
    }
    HandleShip(orderContext) {
        orderContext.SetState(ShippedState())
        return "Order shipped."
    }
    HandleDeliver(orderContext) {
        return "Cannot deliver: Not shipped yet."
    }
    HandleCancel(orderContext) {
        orderContext.SetState(CancelledState())
        return "Cancelled. Refund pending."
    }
    GetStateName() {
        return "Paid"
    }
}

class ShippedState {
    HandlePayment(orderContext) { return "Already paid and shipped." }
    HandleShip(orderContext) { return "Already shipped." }
    HandleDeliver(orderContext) {
        orderContext.SetState(DeliveredState())
        return "Order delivered."
    }
    HandleCancel(orderContext) { return "Cannot cancel: Already shipped." }
    GetStateName() { return "Shipped" }
}

class DeliveredState {
    HandlePayment(orderContext) { return "Complete." }
    HandleShip(orderContext) { return "Complete." }
    HandleDeliver(orderContext) { return "Already delivered." }
    HandleCancel(orderContext) { return "Cannot cancel: Delivered." }
    GetStateName() { return "Delivered" }
}

class CancelledState {
    HandlePayment(orderContext) { return "Cancelled." }
    HandleShip(orderContext) { return "Cancelled." }
    HandleDeliver(orderContext) { return "Cancelled." }
    HandleCancel(orderContext) { return "Already cancelled." }
    GetStateName() { return "Cancelled" }
}

; SHORT FORM: class Order { Pay() => this._state.HandlePayment(this), SetState(s) { this._state := s } }

class OrderContext {
    _orderId := ""
    _currentState := ""
    _stateHistoryArray := []
    
    __New(orderId) {
        this._orderId := orderId
        this._currentState := PendingPaymentState()
        this._stateHistoryArray := ["Created: Pending Payment"]
    }
    
    SetState(newState) {
        local previousStateName := this._currentState.GetStateName()
        this._currentState := newState
        local newStateName := newState.GetStateName()
        this._stateHistoryArray.Push(previousStateName . " -> " . newStateName)
    }
    
    Pay() { return this._currentState.HandlePayment(this) }
    Ship() { return this._currentState.HandleShip(this) }
    Deliver() { return this._currentState.HandleDeliver(this) }
    Cancel() { return this._currentState.HandleCancel(this) }
    
    GetCurrentStateName() { return this._currentState.GetStateName() }
    GetStateHistory() { return this._stateHistoryArray }
}


; ==============================================================================
; PATTERN 21: STRATEGY
; ==============================================================================
; Purpose: Define a family of interchangeable algorithms.
; ==============================================================================

; SHORT FORM: class CreditCardPayment { Pay(a) => "Charged $" . a . " to card " . this._cardNumber }

class CreditCardPaymentStrategy {
    _cardNumberMasked := ""
    _cardHolderName := ""
    
    __New(cardNumber, cardHolderName, expirationDate) {
        local cardLength := StrLen(cardNumber)
        if (cardLength >= 4) {
            this._cardNumberMasked := "****-****-****-" . SubStr(cardNumber, cardLength - 3)
        } else {
            this._cardNumberMasked := "****"
        }
        this._cardHolderName := cardHolderName
    }
    
    Pay(amountValue) {
        return "Charged $" . Format("{:.2f}", amountValue) . " to card " . this._cardNumberMasked
    }
    
    GetName() { return "Credit Card" }
}

class PayPalPaymentStrategy {
    _emailAddress := ""
    
    __New(emailAddress) {
        this._emailAddress := emailAddress
    }
    
    Pay(amountValue) {
        return "Paid $" . Format("{:.2f}", amountValue) . " via PayPal: " . this._emailAddress
    }
    
    GetName() { return "PayPal" }
}

; SHORT FORM: class PaymentProcessor { __New(s) { this._strategy := s }, Process(a) => this._strategy.Pay(a) }

class PaymentProcessor {
    _paymentStrategy := ""
    _transactionHistoryArray := []
    
    __New(initialStrategy := "") {
        this._paymentStrategy := initialStrategy
        this._transactionHistoryArray := []
    }
    
    SetStrategy(newStrategy) {
        this._paymentStrategy := newStrategy
    }
    
    ProcessPayment(amountValue) {
        if (this._paymentStrategy = "") {
            return Result.Fail("No payment method selected")
        }
        
        local paymentResult := this._paymentStrategy.Pay(amountValue)
        
        local transactionRecord := {
            Amount: amountValue,
            Method: this._paymentStrategy.GetName(),
            Result: paymentResult
        }
        this._transactionHistoryArray.Push(transactionRecord)
        
        return Result.Ok(paymentResult)
    }
}


; ==============================================================================
; PATTERN 22: TEMPLATE METHOD
; ==============================================================================
; Purpose: Define algorithm skeleton, let subclasses fill in details.
; ==============================================================================

; SHORT FORM: class DataProcessor { Process() { this.Load(), this.Transform(), this.Save() } }

class DataProcessorTemplate {
    _processedData := ""
    _processingLog := []
    
    ; THE TEMPLATE METHOD - defines the algorithm skeleton
    Process() {
        this._processingLog := []
        
        ; Step 1: Load (abstract)
        this._processingLog.Push("Step 1: Loading...")
        local rawData := this.LoadData()
        
        ; Step 2: Validate (hook with default)
        this._processingLog.Push("Step 2: Validating...")
        local isValid := this.ValidateData(rawData)
        if (!isValid) {
            return Result.Fail("Validation failed")
        }
        
        ; Step 3: Transform (abstract)
        this._processingLog.Push("Step 3: Transforming...")
        local transformedData := this.TransformData(rawData)
        
        ; Step 4: Save (abstract)
        this._processingLog.Push("Step 4: Saving...")
        this.SaveData(transformedData)
        
        this._processedData := transformedData
        return Result.Ok(transformedData)
    }
    
    ; Abstract methods - MUST be implemented
    LoadData() { throw Error("Must implement LoadData") }
    TransformData(rawData) { throw Error("Must implement TransformData") }
    SaveData(processedData) { throw Error("Must implement SaveData") }
    
    ; Hook methods - CAN be overridden
    ValidateData(rawData) {
        return (rawData != "")
    }
    
    GetProcessingLog() {
        return this._processingLog
    }
}

class CsvDataProcessor extends DataProcessorTemplate {
    _inputFilePath := ""
    _outputFilePath := ""
    
    __New(inputPath, outputPath) {
        this._inputFilePath := inputPath
        this._outputFilePath := outputPath
    }
    
    LoadData() {
        return "Name,Age,City`nAlice,30,NYC`nBob,25,LA"
    }
    
    TransformData(rawData) {
        return StrUpper(rawData)
    }
    
    SaveData(processedData) {
        ; Would save to file in real implementation
    }
}


; ==============================================================================
; PATTERN 23: VISITOR
; ==============================================================================
; Purpose: Add operations to classes without changing them.
; ==============================================================================

; SHORT FORM: class Engineer { Accept(v) { v.VisitEngineer(this) } }

class EngineerElement {
    Name := ""
    BaseSalary := 0
    ProgrammingLanguages := []
    YearsExperience := 0
    
    __New(name, baseSalary, languagesArray, yearsExp) {
        this.Name := name
        this.BaseSalary := baseSalary
        this.ProgrammingLanguages := languagesArray
        this.YearsExperience := yearsExp
    }
    
    ; Double dispatch: call the visitor's method for this specific type
    Accept(visitorInstance) {
        return visitorInstance.VisitEngineer(this)
    }
}

class ManagerElement {
    Name := ""
    BaseSalary := 0
    TeamSize := 0
    Department := ""
    
    __New(name, baseSalary, teamSize, department) {
        this.Name := name
        this.BaseSalary := baseSalary
        this.TeamSize := teamSize
        this.Department := department
    }
    
    Accept(visitorInstance) {
        return visitorInstance.VisitManager(this)
    }
}

; SHORT FORM: class SalaryCalculator { VisitEngineer(e) { return e.BaseSalary * 1.1 } }

class SalaryCalculatorVisitor {
    _totalSalaryBudget := 0
    _calculationDetails := []
    
    VisitEngineer(engineerElement) {
        local experienceBonus := engineerElement.BaseSalary * (engineerElement.YearsExperience * 0.02)
        local languageBonus := engineerElement.ProgrammingLanguages.Length * 1000
        local totalSalary := engineerElement.BaseSalary + experienceBonus + languageBonus
        
        this._totalSalaryBudget += totalSalary
        this._calculationDetails.Push(engineerElement.Name . ": $" . Format("{:.0f}", totalSalary))
        
        return totalSalary
    }
    
    VisitManager(managerElement) {
        local teamBonus := managerElement.TeamSize * 500
        local totalSalary := managerElement.BaseSalary + teamBonus
        
        this._totalSalaryBudget += totalSalary
        this._calculationDetails.Push(managerElement.Name . ": $" . Format("{:.0f}", totalSalary))
        
        return totalSalary
    }
    
    GetTotalBudget() { return this._totalSalaryBudget }
    GetCalculationDetails() { return this._calculationDetails }
}


; ╔══════════════════════════════════════════════════════════════════════════════╗
; ║  SECTION 7: DEPENDENCY INJECTION AND SERVICE LAYER                           ║
; ╚══════════════════════════════════════════════════════════════════════════════╝


; ==============================================================================
; Logger Implementation (implements ILogger)
; ==============================================================================

class ConsoleLoggerImplementation extends ILogger {
    _minimumLogLevel := LogLevel.Debug
    _logEntriesArray := []
    
    __New(minimumLevel := "") {
        if (minimumLevel = "") {
            minimumLevel := LogLevel.Debug
        }
        this._minimumLogLevel := minimumLevel
    }
    
    Log(messageText, logLevelValue) {
        if (logLevelValue < this._minimumLogLevel) {
            return
        }
        
        local levelName := LogLevel.ToString(logLevelValue)
        local timestamp := A_Now
        local formattedEntry := "[" . timestamp . "] [" . levelName . "] " . messageText
        
        this._logEntriesArray.Push(formattedEntry)
    }
    
    SetMinimumLevel(minimumLogLevelValue) {
        this._minimumLogLevel := minimumLogLevelValue
    }
    
    GetAllLogs() {
        return this._logEntriesArray
    }
}


; ==============================================================================
; User Repository Implementation (implements IRepository)
; ==============================================================================

; SHORT FORM: class UserRepo extends IRepository { _users := Map(), GetById(id) => this._users.Get(id, ""), Add(u) { this._users[u.Id] := u } }

class InMemoryUserRepository extends IRepository {
    _usersStorageMap := Map()
    _nextIdCounter := 1
    _loggerReference := ""
    
    ; Constructor with DEPENDENCY INJECTION
    __New(loggerInstance) {
        this._loggerReference := loggerInstance
        this._usersStorageMap := Map()
        this._nextIdCounter := 1
    }
    
    GetById(entityIdValue) {
        this._loggerReference.Log("Repository: Getting user by ID " . entityIdValue, LogLevel.Debug)
        if (this._usersStorageMap.Has(entityIdValue)) {
            return this._usersStorageMap.Get(entityIdValue)
        }
        return ""
    }
    
    GetAll() {
        this._loggerReference.Log("Repository: Getting all users", LogLevel.Debug)
        local allUsersArray := []
        for idKey, userObject in this._usersStorageMap {
            allUsersArray.Push(userObject)
        }
        return allUsersArray
    }
    
    Add(entityObject) {
        if (entityObject.Id = 0) {
            entityObject.Id := this._nextIdCounter
            this._nextIdCounter += 1
        }
        this._usersStorageMap.Set(entityObject.Id, entityObject)
        this._loggerReference.Log("Repository: Added user ID " . entityObject.Id, LogLevel.Info)
        return entityObject
    }
    
    Update(entityObject) {
        if (!this._usersStorageMap.Has(entityObject.Id)) {
            return false
        }
        this._usersStorageMap.Set(entityObject.Id, entityObject)
        this._loggerReference.Log("Repository: Updated user ID " . entityObject.Id, LogLevel.Info)
        return true
    }
    
    Delete(entityIdValue) {
        if (!this._usersStorageMap.Has(entityIdValue)) {
            return false
        }
        this._usersStorageMap.Delete(entityIdValue)
        this._loggerReference.Log("Repository: Deleted user ID " . entityIdValue, LogLevel.Info)
        return true
    }
    
    Exists(entityIdValue) {
        return this._usersStorageMap.Has(entityIdValue)
    }
    
    GetByEmail(emailAddress) {
        for idKey, userObject in this._usersStorageMap {
            if (userObject.Email = emailAddress) {
                return userObject
            }
        }
        return ""
    }
}


; ==============================================================================
; User Service Implementation (implements IUserService)
; ==============================================================================

; SHORT FORM: class UserService extends IUserService { __New(repo, logger) { this._repo := repo, this._logger := logger } }

class UserServiceImplementation extends IUserService {
    ; Injected dependencies
    _userRepositoryReference := ""
    _loggerReference := ""
    _notificationServiceReference := ""
    
    ; Constructor with DEPENDENCY INJECTION
    __New(userRepository, logger, notificationService := "") {
        this._userRepositoryReference := userRepository
        this._loggerReference := logger
        this._notificationServiceReference := notificationService
    }
    
    Authenticate(usernameString, passwordString) {
        this._loggerReference.Log("Service: Authenticating " . usernameString, LogLevel.Info)
        
        local foundUser := this._userRepositoryReference.GetByEmail(usernameString)
        
        if (foundUser = "") {
            this._loggerReference.Log("Service: Auth failed - not found", LogLevel.Warning)
            return Result.Fail("Invalid username or password")
        }
        
        if (!foundUser.IsActive) {
            this._loggerReference.Log("Service: Auth failed - inactive", LogLevel.Warning)
            return Result.Fail("Account is inactive")
        }
        
        foundUser.RecordLogin()
        this._userRepositoryReference.Update(foundUser)
        
        this._loggerReference.Log("Service: Auth success: " . usernameString, LogLevel.Info)
        return Result.Ok(foundUser)
    }
    
    Register(userDataObject) {
        this._loggerReference.Log("Service: Registering " . userDataObject.Email, LogLevel.Info)
        
        local validationResult := userDataObject.Validate()
        if (!validationResult.Success) {
            this._loggerReference.Log("Service: Validation error: " . validationResult.Error, LogLevel.Warning)
            return Result.Fail(validationResult.Error)
        }
        
        local existingUser := this._userRepositoryReference.GetByEmail(userDataObject.Email)
        if (existingUser != "") {
            this._loggerReference.Log("Service: Email exists", LogLevel.Warning)
            return Result.Fail("Email already registered")
        }
        
        local savedUser := this._userRepositoryReference.Add(userDataObject)
        
        this._loggerReference.Log("Service: Registered ID " . savedUser.Id, LogLevel.Info)
        return Result.Ok(savedUser)
    }
    
    HasPermission(userIdValue, permissionNameString) {
        local foundUser := this._userRepositoryReference.GetById(userIdValue)
        
        if (foundUser = "") {
            return false
        }
        
        if (foundUser.Role = UserRole.SuperAdmin) {
            return true
        }
        
        if (foundUser.Role = UserRole.Admin) {
            return (permissionNameString != "system.configure")
        }
        
        return false
    }
}


; ==============================================================================
; Notification Service Implementation
; ==============================================================================

class EmailNotificationService extends INotificationService {
    _loggerReference := ""
    _sentNotificationsArray := []
    
    __New(logger) {
        this._loggerReference := logger
        this._sentNotificationsArray := []
    }
    
    Send(recipientIdentifier, messageContent) {
        local notification := {
            Recipient: recipientIdentifier,
            Message: messageContent,
            SentAt: A_Now
        }
        this._sentNotificationsArray.Push(notification)
        
        this._loggerReference.Log("Notification: Sent to " . recipientIdentifier, LogLevel.Info)
        return Result.Ok("Email sent")
    }
    
    SendBulk(arrayOfRecipients, messageContent) {
        for indexNumber, recipientId in arrayOfRecipients {
            this.Send(recipientId, messageContent)
        }
        return Result.Ok("Sent " . arrayOfRecipients.Length . " emails")
    }
}


; ==============================================================================
; DEPENDENCY INJECTION CONTAINER
; ==============================================================================

; SHORT FORM: class DIContainer { static _reg := Map(), static Register(n, f) { this._reg[n] := f }, static Resolve(n) => this._reg[n]() }

class DependencyInjectionContainer {
    static _serviceRegistryMap := Map()
    static _singletonCacheMap := Map()
    
    static RegisterTransient(serviceName, factoryFunction) {
        DependencyInjectionContainer._serviceRegistryMap.Set(serviceName, {
            Factory: factoryFunction,
            IsSingleton: false
        })
    }
    
    static RegisterSingleton(serviceName, factoryFunction) {
        DependencyInjectionContainer._serviceRegistryMap.Set(serviceName, {
            Factory: factoryFunction,
            IsSingleton: true
        })
    }
    
    static Resolve(serviceName) {
        if (!DependencyInjectionContainer._serviceRegistryMap.Has(serviceName)) {
            throw Error("Service not registered: " . serviceName)
        }
        
        local registration := DependencyInjectionContainer._serviceRegistryMap.Get(serviceName)
        
        if (registration.IsSingleton) {
            if (DependencyInjectionContainer._singletonCacheMap.Has(serviceName)) {
                return DependencyInjectionContainer._singletonCacheMap.Get(serviceName)
            }
        }
        
        local instance := registration.Factory.Call()
        
        if (registration.IsSingleton) {
            DependencyInjectionContainer._singletonCacheMap.Set(serviceName, instance)
        }
        
        return instance
    }
    
    static ConfigureServices() {
        DependencyInjectionContainer.RegisterSingleton("ILogger", () => ConsoleLoggerImplementation(LogLevel.Debug))
        
        DependencyInjectionContainer.RegisterSingleton("IUserRepository", () => InMemoryUserRepository(DependencyInjectionContainer.Resolve("ILogger")))
        
        DependencyInjectionContainer.RegisterSingleton("INotificationService", () => EmailNotificationService(DependencyInjectionContainer.Resolve("ILogger")))
        
        DependencyInjectionContainer.RegisterTransient("IUserService", () => UserServiceImplementation(
            DependencyInjectionContainer.Resolve("IUserRepository"),
            DependencyInjectionContainer.Resolve("ILogger"),
            DependencyInjectionContainer.Resolve("INotificationService")
        ))
    }
}


; ╔══════════════════════════════════════════════════════════════════════════════╗
; ║  SECTION 8: DEMONSTRATION                                                    ║
; ╚══════════════════════════════════════════════════════════════════════════════╝

DemonstrateAllPatterns() {
    local outputMessages := []
    
    outputMessages.Push("═══════════════════════════════════════════════════")
    outputMessages.Push("     DESIGN PATTERNS DEMONSTRATION - AHK V2        ")
    outputMessages.Push("═══════════════════════════════════════════════════")
    
    ; 1. Configure DI Container
    outputMessages.Push("`n--- DEPENDENCY INJECTION SETUP ---")
    DependencyInjectionContainer.ConfigureServices()
    outputMessages.Push("DI Container configured")
    
    ; 2. Resolve and use services
    outputMessages.Push("`n--- SERVICE LAYER DEMO ---")
    local userService := DependencyInjectionContainer.Resolve("IUserService")
    local logger := DependencyInjectionContainer.Resolve("ILogger")
    
    local newUser := User(0, "John Doe", "john@example.com", UserRole.User)
    local registerResult := userService.Register(newUser)
    outputMessages.Push("Register: " . (registerResult.Success ? "Success ID: " . registerResult.Value.Id : "Failed"))
    
    local authResult := userService.Authenticate("john@example.com", "password")
    outputMessages.Push("Auth: " . (authResult.Success ? "Success" : "Failed"))
    
    ; 3. Singleton
    outputMessages.Push("`n--- SINGLETON PATTERN ---")
    local config1 := ConfigurationManagerSingleton.Instance
    local config2 := ConfigurationManagerSingleton.Instance
    outputMessages.Push("Same instance? " . (config1 = config2 ? "Yes" : "No"))
    outputMessages.Push("App: " . config1.GetConfigurationValue("ApplicationName"))
    
    ; 4. Factory Method
    outputMessages.Push("`n--- FACTORY METHOD ---")
    local pdfCreator := PdfDocumentCreator()
    local pdfDoc := pdfCreator.RenderDocument()
    outputMessages.Push("Created: " . pdfDoc.GetFileExtension())
    
    ; 5. Builder
    outputMessages.Push("`n--- BUILDER PATTERN ---")
    local email := EmailMessageBuilder()
        .SetRecipient("user@example.com")
        .SetSender("noreply@company.com")
        .SetSubject("Welcome!")
        .SetHighPriority()
        .Build()
    outputMessages.Push("Built email to: " . email.RecipientAddress . " Priority: " . (email.IsHighPriority ? "High" : "Normal"))
    
    ; 6. Decorator
    outputMessages.Push("`n--- DECORATOR PATTERN ---")
    local plainText := PlainTextComponent("Hello World")
    local boldText := BoldTextDecorator(plainText)
    local boldItalicText := ItalicTextDecorator(boldText)
    outputMessages.Push("Plain: " . plainText.GetContent())
    outputMessages.Push("Bold: " . boldText.GetContent())
    outputMessages.Push("Bold+Italic: " . boldItalicText.GetContent())
    
    ; 7. Observer
    outputMessages.Push("`n--- OBSERVER PATTERN ---")
    local stock := StockPriceSubject("AAPL", 150.00)
    local display := PriceDisplayObserver("Main")
    local alerter := AlertObserver(5)
    stock.Attach(display)
    stock.Attach(alerter)
    stock.SetPrice(160.00)
    outputMessages.Push(display.GetLastDisplay())
    local alerts := alerter.GetAlerts()
    if (alerts.Length > 0) {
        outputMessages.Push(alerts[1])
    }
    
    ; 8. Strategy
    outputMessages.Push("`n--- STRATEGY PATTERN ---")
    local paymentProcessor := PaymentProcessor()
    paymentProcessor.SetStrategy(CreditCardPaymentStrategy("4111111111111111", "John", "12/25"))
    local payResult := paymentProcessor.ProcessPayment(99.99)
    outputMessages.Push(payResult.Value)
    
    paymentProcessor.SetStrategy(PayPalPaymentStrategy("john@example.com"))
    payResult := paymentProcessor.ProcessPayment(49.99)
    outputMessages.Push(payResult.Value)
    
    ; 9. Command
    outputMessages.Push("`n--- COMMAND PATTERN ---")
    local editor := TextEditorReceiver()
    local invoker := CommandInvoker()
    invoker.ExecuteCommand(InsertTextCommand(editor, "Hello "))
    invoker.ExecuteCommand(InsertTextCommand(editor, "World!"))
    outputMessages.Push("After inserts: '" . editor.GetText() . "'")
    invoker.Undo()
    outputMessages.Push("After undo: '" . editor.GetText() . "'")
    
    ; 10. State
    outputMessages.Push("`n--- STATE PATTERN ---")
    local order := OrderContext("ORD-001")
    outputMessages.Push("Initial: " . order.GetCurrentStateName())
    outputMessages.Push(order.Pay())
    outputMessages.Push("After pay: " . order.GetCurrentStateName())
    outputMessages.Push(order.Ship())
    outputMessages.Push("After ship: " . order.GetCurrentStateName())
    
    ; Show logs
    outputMessages.Push("`n--- LOG OUTPUT ---")
    local allLogs := logger.GetAllLogs()
    local logCount := 0
    for indexNumber, logEntry in allLogs {
        if (logCount < 5) {
            outputMessages.Push(logEntry)
            logCount += 1
        }
    }
    if (allLogs.Length > 5) {
        outputMessages.Push("... and " . (allLogs.Length - 5) . " more entries")
    }
    
    outputMessages.Push("`n═══════════════════════════════════════════════════")
    outputMessages.Push("                DEMONSTRATION COMPLETE               ")
    outputMessages.Push("═══════════════════════════════════════════════════")
    
    local fullOutput := ""
    for indexNumber, message in outputMessages {
        fullOutput := fullOutput . message . "`n"
    }
    
    return fullOutput
}


; ╔══════════════════════════════════════════════════════════════════════════════╗
; ║  SECTION 9: COMPREHENSIVE EXPLANATION OF ALL CODE BLOCKS                     ║
; ╚══════════════════════════════════════════════════════════════════════════════╝

/*
================================================================================
COMPREHENSIVE EXPLANATION OF ALL DEMONSTRATED CONCEPTS
================================================================================

This file demonstrates professional software engineering patterns in AHK v2.

--------------------------------------------------------------------------------
1. CUSTOM TYPES (ENUMERATIONS)
--------------------------------------------------------------------------------

What they are:
    Custom types let us create our own "categories" of values. Instead of using
    raw numbers or strings like "1" or "admin", we create named constants that
    make code self-documenting and prevent typos.

How LogLevel works:
    - It's a class with STATIC properties (LogLevel.Debug, LogLevel.Info, etc.)
    - Static means the values belong to the class itself, not to instances
    - We never write "new LogLevel()" - we just use LogLevel.Error directly
    - The ToString method converts numbers back to readable names

The Result class:
    - A "value object" that wraps the outcome of any operation
    - Contains Success (true/false), Value (the data), and Error (message)
    - Factory methods Ok() and Fail() create success/failure results
    - This avoids throwing exceptions for expected failures

--------------------------------------------------------------------------------
2. INTERFACES (CONTRACTS)
--------------------------------------------------------------------------------

What they are:
    Interfaces define WHAT an object must do, without specifying HOW.
    Any class that "implements" an interface promises to provide those methods.

Why use them:
    - DECOUPLING: Code depends on interfaces, not concrete classes
    - TESTABILITY: You can create mock implementations for testing
    - FLEXIBILITY: Swap implementations without changing dependent code

How they work in AHK:
    - AHK doesn't have native interfaces, so we simulate them
    - Interface methods throw errors if called directly
    - Classes that extend interfaces MUST override all methods

--------------------------------------------------------------------------------
3. CREATIONAL PATTERNS (How objects are created)
--------------------------------------------------------------------------------

SINGLETON:
    Purpose: Ensure only ONE instance exists globally.
    How: Static property stores instance; getter creates if needed.
    Use for: Configuration, logging, connection pools.

FACTORY METHOD:
    Purpose: Let subclasses decide which class to instantiate.
    How: Abstract CreateDocument(); subclasses override.
    Use for: When exact type isn't known until runtime.

ABSTRACT FACTORY:
    Purpose: Create FAMILIES of related objects.
    How: WindowsFactory creates Windows controls; MacFactory creates Mac controls.
    Use for: Cross-platform UI, database providers.

BUILDER:
    Purpose: Construct complex objects step by step.
    How: Each setter returns "this" for chaining; Build() returns result.
    Use for: Objects with many optional parameters.

PROTOTYPE:
    Purpose: Create new objects by copying existing ones.
    How: Clone() method creates a copy with identical properties.
    Use for: When object creation is expensive.

--------------------------------------------------------------------------------
4. STRUCTURAL PATTERNS (How objects are composed)
--------------------------------------------------------------------------------

ADAPTER:
    Purpose: Convert one interface to another.
    How: Wrapper translates calls between interfaces.
    Use for: Integrating with legacy code or third-party libraries.

BRIDGE:
    Purpose: Separate abstraction from implementation.
    How: Abstraction holds reference to implementor.
    Use for: When both should be extensible independently.

COMPOSITE:
    Purpose: Treat individual objects and compositions uniformly.
    How: Files and Folders implement same interface; Folders contain children.
    Use for: Tree structures (file systems, organization charts).

DECORATOR:
    Purpose: Add responsibilities dynamically.
    How: Decorators wrap component, add behavior, delegate rest.
    Use for: Adding features without modifying original classes.

FACADE:
    Purpose: Simplified interface to complex subsystem.
    How: One method hides multiple internal operations.
    Use for: Simplifying complex APIs.

FLYWEIGHT:
    Purpose: Share common state among many objects.
    How: Factory returns shared instances; extrinsic state passed as params.
    Use for: Large numbers of similar objects (text rendering).

PROXY:
    Purpose: Control access to another object.
    Types: Virtual (lazy loading), Protection (access control), Caching.
    Use for: Lazy loading, access control, logging, caching.

--------------------------------------------------------------------------------
5. BEHAVIORAL PATTERNS (How objects communicate)
--------------------------------------------------------------------------------

CHAIN OF RESPONSIBILITY:
    Purpose: Pass requests along a chain of handlers.
    How: Each handler decides handle or pass to next.
    Use for: Event handling, approval workflows.

COMMAND:
    Purpose: Encapsulate request as object.
    How: Commands have Execute() and Undo(); Invoker manages history.
    Use for: Undo functionality, macro recording.

INTERPRETER:
    Purpose: Define grammar and interpret expressions.
    How: Terminal and non-terminal expressions; recursive Interpret().
    Use for: Simple languages, calculators.

ITERATOR:
    Purpose: Access elements sequentially without exposing structure.
    How: HasNext() and Next() methods.
    Use for: Custom collections, different traversal orders.

MEDIATOR:
    Purpose: Define how objects interact without direct references.
    How: Mediator routes all communication.
    Use for: Chat systems, GUI coordination.

MEMENTO:
    Purpose: Capture and restore object state.
    How: Originator creates Mementos; Caretaker stores them.
    Use for: Undo, save games, checkpoints.

OBSERVER:
    Purpose: Notify objects when another changes.
    How: Subject maintains observers; Notify() calls all Update().
    Use for: Event systems, data binding.

STATE:
    Purpose: Change behavior when state changes.
    How: Context delegates to current State object.
    Use for: State machines, order processing.

STRATEGY:
    Purpose: Interchangeable algorithms.
    How: Context holds strategy; strategy can be changed at runtime.
    Use for: Multiple algorithms, payment methods.

TEMPLATE METHOD:
    Purpose: Define algorithm skeleton, let subclasses fill details.
    How: Base class defines steps; abstract methods must be overridden.
    Use for: Frameworks, data processing pipelines.

VISITOR:
    Purpose: Add operations without changing classes.
    How: Elements Accept(visitor); visitor has method per element type.
    Use for: Report generation, code analysis.

--------------------------------------------------------------------------------
6. DEPENDENCY INJECTION
--------------------------------------------------------------------------------

What is it?
    Instead of a class creating its dependencies, they are "injected" (passed in).
    This makes classes more testable and flexible.

How it works:
    - Services receive dependencies through constructors
    - UserService receives IUserRepository and ILogger
    - It doesn't know which concrete implementations are used

The DI Container:
    - RegisterSingleton: Same instance every time
    - RegisterTransient: New instance each time
    - Resolve: Gets an instance by service name

--------------------------------------------------------------------------------
7. KEY AUTOHOTKEY V2 SYNTAX
--------------------------------------------------------------------------------

Classes and Objects:
    - "class ClassName { }" defines a class
    - "extends ParentClass" creates inheritance
    - "__New()" is the constructor
    - "this" refers to the current instance

Properties:
    - "PropertyName := value" defines instance property
    - "static PropertyName := value" defines class property
    - "{ get { } }" defines a property getter

Methods:
    - "MethodName(params) { }" defines a method
    - "static MethodName()" defines a class method
    - "super.MethodName()" calls the parent's method

Maps and Arrays:
    - "Map()" creates a key-value dictionary
    - "[]" creates an array
    - ".Push()" adds to array end
    - ".Get(key, default)" retrieves from map

================================================================================
END OF EXPLANATION
================================================================================
*/
