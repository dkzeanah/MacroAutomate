; ╔══════════════════════════════════════════════════════════════════════════════╗
; ║  DESIGN PATTERNS REFERENCE GUI                                               ║
; ║  A comprehensive tabbed reference for all 23 Gang of Four patterns           ║
; ║  Plus architectural concepts like DI, Repository, Service Layer              ║
; ╚══════════════════════════════════════════════════════════════════════════════╝

#Requires AutoHotkey v2.0
#SingleInstance Force

; ══════════════════════════════════════════════════════════════════════════════
; MAIN APPLICATION CLASS
; ══════════════════════════════════════════════════════════════════════════════

class DesignPatternsReferenceApp {
    ; Store references to GUI elements
    mainGui := ""
    tabControl := ""
    patternListBox := ""
    nameText := ""
    definitionEdit := ""
    whyHowEdit := ""
    codeEdit := ""
    copyButton := ""
    
    ; Store all pattern data
    patterns := Map()
    currentCategory := ""
    
    __New() {
        this.InitializePatternData()
        this.CreateGui()
    }
    
    ; ══════════════════════════════════════════════════════════════════════════
    ; CREATE THE MAIN GUI
    ; ══════════════════════════════════════════════════════════════════════════
    
    CreateGui() {
        ; Create main window
        this.mainGui := Gui("+Resize +MinSize900x700")
        this.mainGui.Title := "Design Patterns Reference - Gang of Four + Architecture"
        this.mainGui.BackColor := "1a1a2e"
        
        ; Add title label
        titleLabel := this.mainGui.AddText("x20 y10 w860 h30 Center", "Design Patterns Reference")
        titleLabel.SetFont("s16 Bold cWhite", "Segoe UI")
        
        ; Create Tab control with categories
        this.tabControl := this.mainGui.AddTab3("x10 y50 w880 h640 Background2d2d44", [
            "Creational",
            "━━━━━",
            "Structural", 
            "━━━━━",
            "Behavioral",
            "━━━━━",
            "Architecture"
        ])
        this.tabControl.SetFont("s10 cWhite", "Segoe UI")
        
        ; Build each tab
        this.BuildCreationalTab()
        this.BuildSeparatorTab(2)
        this.BuildStructuralTab()
        this.BuildSeparatorTab(4)
        this.BuildBehavioralTab()
        this.BuildSeparatorTab(6)
        this.BuildArchitectureTab()
        
        ; Handle tab change
        this.tabControl.OnEvent("Change", (ctrl, *) => this.OnTabChange(ctrl))
        
        ; Handle window resize
        this.mainGui.OnEvent("Size", (thisGui, minMax, w, h) => this.OnResize(w, h))
        
        ; Show the GUI
        this.mainGui.Show("w900 h700")
        
        ; Select first pattern in first tab
        this.tabControl.Choose(1)
        this.OnTabChange(this.tabControl)
    }
    
    ; ══════════════════════════════════════════════════════════════════════════
    ; BUILD INDIVIDUAL TABS
    ; ══════════════════════════════════════════════════════════════════════════
    
    BuildCreationalTab() {
        this.tabControl.UseTab(1)
        this.BuildPatternLayout("Creational", [
            "Singleton",
            "Factory Method", 
            "Abstract Factory",
            "Builder",
            "Prototype"
        ])
    }
    
    BuildStructuralTab() {
        this.tabControl.UseTab(3)
        this.BuildPatternLayout("Structural", [
            "Adapter",
            "Bridge",
            "Composite",
            "Decorator",
            "Facade",
            "Flyweight",
            "Proxy"
        ])
    }
    
    BuildBehavioralTab() {
        this.tabControl.UseTab(5)
        this.BuildPatternLayout("Behavioral", [
            "Chain of Responsibility",
            "Command",
            "Interpreter",
            "Iterator",
            "Mediator",
            "Memento",
            "Observer",
            "State",
            "Strategy",
            "Template Method",
            "Visitor"
        ])
    }
    
    BuildArchitectureTab() {
        this.tabControl.UseTab(7)
        this.BuildPatternLayout("Architecture", [
            "Dependency Injection",
            "Repository Pattern",
            "Service Layer",
            "Interfaces",
            "Value Objects"
        ])
    }
    
    BuildSeparatorTab(tabNum) {
        this.tabControl.UseTab(tabNum)
        sepLabel := this.mainGui.AddText("x200 y300 w500 h40 Center", "── Category Separator ──")
        sepLabel.SetFont("s14 c666666 Italic", "Segoe UI")
    }
    
    ; ══════════════════════════════════════════════════════════════════════════
    ; BUILD PATTERN LAYOUT (Used by each category tab)
    ; ══════════════════════════════════════════════════════════════════════════
    
    BuildPatternLayout(category, patternNames) {
        ; Left side - Pattern list
        listLabel := this.mainGui.AddText("x20 y90 w180 h20", "Select Pattern:")
        listLabel.SetFont("s10 Bold cWhite", "Segoe UI")
        
        patternList := this.mainGui.AddListBox("x20 y115 w180 h520 Background3d3d5c cWhite", patternNames)
        patternList.SetFont("s10", "Consolas")
        patternList.OnEvent("Change", (ctrl, *) => this.OnPatternSelect(ctrl, category))
        
        ; Store reference for this tab
        patternList.category := category
        
        ; Right side - Pattern details
        ; Name
        nameLabel := this.mainGui.AddText("x220 y90 w100 h20", "Pattern:")
        nameLabel.SetFont("s10 Bold cWhite", "Segoe UI")
        
        nameDisplay := this.mainGui.AddText("x220 y110 w640 h25 Background3d3d5c c00ff88", "")
        nameDisplay.SetFont("s12 Bold", "Consolas")
        
        ; Definition
        defLabel := this.mainGui.AddText("x220 y145 w100 h20", "Definition:")
        defLabel.SetFont("s10 Bold cWhite", "Segoe UI")
        
        defEdit := this.mainGui.AddEdit("x220 y165 w640 h60 +ReadOnly +Multi Background3d3d5c cWhite", "")
        defEdit.SetFont("s9", "Segoe UI")
        
        ; Why / How
        whyLabel := this.mainGui.AddText("x220 y235 w200 h20", "Why Use It / How It Works:")
        whyLabel.SetFont("s10 Bold cWhite", "Segoe UI")
        
        whyEdit := this.mainGui.AddEdit("x220 y255 w640 h100 +ReadOnly +Multi +VScroll Background3d3d5c cWhite", "")
        whyEdit.SetFont("s9", "Segoe UI")
        
        ; Code Example
        codeLabel := this.mainGui.AddText("x220 y365 w200 h20", "Code Example (AHK v2):")
        codeLabel.SetFont("s10 Bold cWhite", "Segoe UI")
        
        codeEdit := this.mainGui.AddEdit("x220 y385 w640 h200 +ReadOnly +Multi +VScroll +HScroll Background1e1e2e cLime", "")
        codeEdit.SetFont("s9", "Consolas")
        
        ; Copy button
        copyBtn := this.mainGui.AddButton("x220 y595 w150 h30", "📋 Copy Code")
        copyBtn.SetFont("s10", "Segoe UI")
        copyBtn.OnEvent("Click", (ctrl, *) => this.CopyCode(codeEdit))
        
        ; Store references with category prefix
        this.patterns[category . "_list"] := patternList
        this.patterns[category . "_name"] := nameDisplay
        this.patterns[category . "_def"] := defEdit
        this.patterns[category . "_why"] := whyEdit
        this.patterns[category . "_code"] := codeEdit
    }
    
    ; ══════════════════════════════════════════════════════════════════════════
    ; EVENT HANDLERS
    ; ══════════════════════════════════════════════════════════════════════════
    
    OnTabChange(ctrl) {
        tabIndex := ctrl.Value
        categories := ["Creational", "", "Structural", "", "Behavioral", "", "Architecture"]
        
        if (tabIndex > 0 && tabIndex <= categories.Length) {
            category := categories[tabIndex]
            if (category != "" && this.patterns.Has(category . "_list")) {
                this.currentCategory := category
                listBox := this.patterns[category . "_list"]
                if (listBox.Value = 0) {
                    listBox.Choose(1)
                }
                this.OnPatternSelect(listBox, category)
            }
        }
    }
    
    OnPatternSelect(ctrl, category) {
        if (ctrl.Value = 0) {
            return
        }
        
        selectedPattern := ctrl.Text
        patternData := this.GetPatternData(category, selectedPattern)
        
        if (patternData != "") {
            this.patterns[category . "_name"].Value := patternData.Name
            this.patterns[category . "_def"].Value := patternData.Definition
            this.patterns[category . "_why"].Value := patternData.WhyHow
            this.patterns[category . "_code"].Value := patternData.Code
        }
    }
    
    CopyCode(codeEdit) {
        A_Clipboard := codeEdit.Value
        ToolTip("Code copied to clipboard!")
        SetTimer(() => ToolTip(), -2000)
    }
    
    OnResize(w, h) {
        ; Handle resize if needed
    }
    
    ; ══════════════════════════════════════════════════════════════════════════
    ; PATTERN DATA INITIALIZATION
    ; ══════════════════════════════════════════════════════════════════════════
    
    InitializePatternData() {
        this.patternData := Map()
        
        ; ──────────────────────────────────────────────────────────────────────
        ; CREATIONAL PATTERNS
        ; ──────────────────────────────────────────────────────────────────────
        
        this.patternData["Creational_Singleton"] := {
            Name: "Singleton",
            Definition: "Ensures a class has only ONE instance and provides a global point of access to it. The single instance is created lazily (only when first requested) and reused for all subsequent requests.",
            WhyHow: "WHY USE IT:`n• When exactly one object is needed to coordinate actions across the system`n• For shared resources like configuration managers, connection pools, or loggers`n• To control access to a shared resource`n`nHOW IT WORKS:`n• Private/hidden constructor prevents direct instantiation`n• Static property stores the single instance`n• Static getter creates instance on first access, returns existing instance thereafter`n• All code receives the same instance",
            Code: "
class ConfigManager {
    ; Static variable stores the ONE instance
    static _instance := `"`"
    
    ; Static property with getter - this is the access point
    static Instance {
        get {
            ; If no instance exists yet, create one
            if (ConfigManager._instance = `"`") {
                ConfigManager._instance := ConfigManager()
            }
            ; Return the single instance
            return ConfigManager._instance
        }
    }
    
    ; Instance properties and methods
    _settings := Map()
    
    __New() {
        ; Private constructor - only called once internally
        this._settings.Set(`"AppName`", `"My Application`")
        this._settings.Set(`"Version`", `"1.0.0`")
    }
    
    Get(key, default := `"`") {
        return this._settings.Get(key, default)
    }
    
    Set(key, value) {
        this._settings.Set(key, value)
    }
}

; USAGE - Both variables reference the SAME instance
config1 := ConfigManager.Instance
config2 := ConfigManager.Instance

config1.Set(`"Theme`", `"Dark`")
MsgBox(config2.Get(`"Theme`"))  ; Shows `"Dark`" - same instance!
MsgBox(config1 = config2)       ; Shows 1 (true) - identical objects
"
        }
        
        this.patternData["Creational_Factory Method"] := {
            Name: "Factory Method",
            Definition: "Defines an interface for creating an object, but lets subclasses decide which class to instantiate. Factory Method lets a class defer instantiation to subclasses.",
            WhyHow: "WHY USE IT:`n• When a class can't anticipate the type of objects it needs to create`n• When you want subclasses to specify the objects they create`n• To encapsulate object creation logic`n• To decouple client code from concrete classes`n`nHOW IT WORKS:`n• Abstract Creator class declares the factory method`n• Concrete Creators override the factory method to return specific products`n• Client code works with Creator interface, not concrete classes`n• New product types = new Creator subclasses (no existing code changes)",
            Code: "
; Abstract Product - defines interface
class Document {
    content := `"`"
    Render() {
        throw Error(`"Must implement Render`")
    }
    GetExtension() {
        throw Error(`"Must implement GetExtension`")
    }
}

; Concrete Products
class PdfDocument extends Document {
    Render() {
        this.content := `"PDF content rendered`"
        return this.content
    }
    GetExtension() {
        return `".pdf`"
    }
}

class HtmlDocument extends Document {
    Render() {
        this.content := `"<html><body>HTML content</body></html>`"
        return this.content
    }
    GetExtension() {
        return `".html`"
    }
}

; Abstract Creator - declares factory method
class DocumentCreator {
    ; THE FACTORY METHOD - subclasses override this
    CreateDocument() {
        throw Error(`"Subclass must implement CreateDocument`")
    }
    
    ; Template method that uses the factory method
    GenerateDocument() {
        doc := this.CreateDocument()  ; Calls overridden method
        doc.Render()
        return doc
    }
}

; Concrete Creators - implement the factory method
class PdfCreator extends DocumentCreator {
    CreateDocument() {
        return PdfDocument()
    }
}

class HtmlCreator extends DocumentCreator {
    CreateDocument() {
        return HtmlDocument()
    }
}

; USAGE - Client code works with abstract Creator
creator := PdfCreator()          ; or HtmlCreator()
doc := creator.GenerateDocument()
MsgBox(doc.GetExtension())       ; Shows .pdf
"
        }
        
        this.patternData["Creational_Abstract Factory"] := {
            Name: "Abstract Factory",
            Definition: "Provides an interface for creating families of related or dependent objects without specifying their concrete classes. Creates entire product families that work together.",
            WhyHow: "WHY USE IT:`n• When you need to create families of related objects`n• When products from one family shouldn't mix with another`n• For cross-platform UI (Windows widgets vs Mac widgets)`n• To ensure consistency among products`n`nHOW IT WORKS:`n• Abstract Factory interface declares creation methods for each product type`n• Concrete Factories implement all creation methods for one family`n• Products from same factory are guaranteed compatible`n• Switching families = changing one factory instance",
            Code: "
; Abstract Products
class Button {
    Render() {
        throw Error(`"Must implement`")
    }
}

class TextBox {
    Render() {
        throw Error(`"Must implement`")
    }
}

; Windows Family
class WindowsButton extends Button {
    Render() {
        return `"[====Windows Button====]`"
    }
}

class WindowsTextBox extends TextBox {
    Render() {
        return `"|____Windows TextBox____|`"
    }
}

; Mac Family
class MacButton extends Button {
    Render() {
        return `"(  Mac Button  )`"
    }
}

class MacTextBox extends TextBox {
    Render() {
        return `"[  Mac TextBox  ]`"
    }
}

; Abstract Factory
class UIFactory {
    CreateButton() {
        throw Error(`"Must implement`")
    }
    CreateTextBox() {
        throw Error(`"Must implement`")
    }
}

; Concrete Factories
class WindowsUIFactory extends UIFactory {
    CreateButton() {
        return WindowsButton()
    }
    CreateTextBox() {
        return WindowsTextBox()
    }
}

class MacUIFactory extends UIFactory {
    CreateButton() {
        return MacButton()
    }
    CreateTextBox() {
        return MacTextBox()
    }
}

; USAGE - Switch entire UI family by changing factory
factory := WindowsUIFactory()    ; or MacUIFactory()
btn := factory.CreateButton()
txt := factory.CreateTextBox()
MsgBox(btn.Render() . `"`n`" . txt.Render())
"
        }
        
        this.patternData["Creational_Builder"] := {
            Name: "Builder",
            Definition: "Separates the construction of a complex object from its representation, allowing the same construction process to create different representations. Builds objects step-by-step.",
            WhyHow: "WHY USE IT:`n• When objects have many optional parameters`n• To avoid 'telescoping constructors' (many constructor overloads)`n• When construction involves multiple steps`n• To create immutable objects with many fields`n`nHOW IT WORKS:`n• Builder class has methods for each configurable part`n• Each method returns 'this' for method chaining (fluent interface)`n• Build() method returns the finished object`n• Builder can be reused or reset after Build()",
            Code: "
; The complex object to build
class Email {
    To := `"`"
    From := `"`"
    Subject := `"`"
    Body := `"`"
    CC := []
    Attachments := []
    IsHighPriority := false
    IsHtml := false
}

; The Builder - constructs Email step by step
class EmailBuilder {
    _email := `"`"
    
    __New() {
        this._email := Email()
    }
    
    ; Each method sets one property and returns 'this'
    ; This enables method chaining: builder.To().From().Subject()
    
    SetTo(recipient) {
        this._email.To := recipient
        return this    ; Return this for chaining
    }
    
    SetFrom(sender) {
        this._email.From := sender
        return this
    }
    
    SetSubject(subject) {
        this._email.Subject := subject
        return this
    }
    
    SetBody(body) {
        this._email.Body := body
        return this
    }
    
    AddCC(ccRecipient) {
        this._email.CC.Push(ccRecipient)
        return this
    }
    
    AddAttachment(filePath) {
        this._email.Attachments.Push(filePath)
        return this
    }
    
    SetHighPriority(isHigh := true) {
        this._email.IsHighPriority := isHigh
        return this
    }
    
    SetHtml(isHtml := true) {
        this._email.IsHtml := isHtml
        return this
    }
    
    ; Final step - return the constructed object
    Build() {
        finishedEmail := this._email
        this._email := Email()  ; Reset for reuse
        return finishedEmail
    }
}

; USAGE - Fluent interface with method chaining
email := EmailBuilder()
    .SetTo(`"user@example.com`")
    .SetFrom(`"noreply@company.com`")
    .SetSubject(`"Welcome!`")
    .SetBody(`"Thanks for signing up.`")
    .AddCC(`"manager@company.com`")
    .SetHighPriority()
    .Build()

MsgBox(`"To: `" . email.To . `"`nPriority: `" . (email.IsHighPriority ? `"High`" : `"Normal`"))
"
        }
        
        this.patternData["Creational_Prototype"] := {
            Name: "Prototype",
            Definition: "Specifies the kinds of objects to create using a prototypical instance, and creates new objects by copying this prototype. Cloning instead of instantiating.",
            WhyHow: "WHY USE IT:`n• When object creation is expensive (database load, complex calculation)`n• When you need copies of objects with most properties the same`n• To avoid subclassing for every variation`n• When classes to instantiate are specified at runtime`n`nHOW IT WORKS:`n• Prototype object has a Clone() method`n• Clone creates a new instance and copies all properties`n• Prototype Registry can store named prototypes for retrieval`n• Client requests clones instead of calling constructors",
            Code: "
; Prototype class with Clone method
class Shape {
    X := 0
    Y := 0
    Width := 100
    Height := 100
    Color := `"Black`"
    Type := `"Rectangle`"
    
    ; THE KEY METHOD - creates a copy of this object
    Clone() {
        copy := Shape()
        copy.X := this.X
        copy.Y := this.Y
        copy.Width := this.Width
        copy.Height := this.Height
        copy.Color := this.Color
        copy.Type := this.Type
        return copy
    }
    
    ToString() {
        return this.Type . `" at (`" . this.X . `",`" . this.Y . `") - `" . this.Color
    }
}

; Prototype Registry - stores reusable prototypes
class ShapeRegistry {
    static _prototypes := Map()
    
    static Register(name, prototype) {
        ShapeRegistry._prototypes.Set(name, prototype)
    }
    
    static GetClone(name) {
        if (ShapeRegistry._prototypes.Has(name)) {
            return ShapeRegistry._prototypes.Get(name).Clone()
        }
        return `"`"
    }
}

; USAGE - Create and register prototypes
redSquare := Shape()
redSquare.Color := `"Red`"
redSquare.Type := `"Square`"
redSquare.Width := 50
redSquare.Height := 50

blueCircle := Shape()
blueCircle.Color := `"Blue`"
blueCircle.Type := `"Circle`"

ShapeRegistry.Register(`"RedSquare`", redSquare)
ShapeRegistry.Register(`"BlueCircle`", blueCircle)

; Get clones - much faster than recreating
shape1 := ShapeRegistry.GetClone(`"RedSquare`")
shape1.X := 100  ; Modify the clone
shape1.Y := 200

shape2 := ShapeRegistry.GetClone(`"RedSquare`")
shape2.X := 300  ; Different position

MsgBox(shape1.ToString() . `"`n`" . shape2.ToString())
"
        }
        
        ; ──────────────────────────────────────────────────────────────────────
        ; STRUCTURAL PATTERNS
        ; ──────────────────────────────────────────────────────────────────────
        
        this.patternData["Structural_Adapter"] := {
            Name: "Adapter",
            Definition: "Converts the interface of a class into another interface clients expect. Adapter lets classes work together that couldn't otherwise because of incompatible interfaces.",
            WhyHow: "WHY USE IT:`n• To use an existing class with an incompatible interface`n• To integrate legacy code with new systems`n• To work with third-party libraries that have different interfaces`n• To create a reusable class that cooperates with unrelated classes`n`nHOW IT WORKS:`n• Adapter wraps the 'adaptee' (incompatible class)`n• Adapter implements the target interface expected by client`n• Adapter translates client calls to adaptee's format`n• Client code works with adapter as if it were the target",
            Code: "
; Target interface - what client expects
class IModernLogger {
    Log(message, level) {
        throw Error(`"Must implement Log`")
    }
}

; Adaptee - existing class with incompatible interface
class LegacyLogger {
    ; Old method signature that doesn't match what we need
    WriteLog(typeCode, msg, timestamp) {
        return `"[`" . timestamp . `"] `" . typeCode . `": `" . msg
    }
}

; ADAPTER - bridges the gap between interfaces
class LoggerAdapter extends IModernLogger {
    _legacyLogger := `"`"
    
    __New(legacyLogger) {
        this._legacyLogger := legacyLogger
    }
    
    ; Implement target interface
    Log(message, level) {
        ; Translate level to legacy type code
        typeCode := `"INFO`"
        if (level >= 4) {
            typeCode := `"ERROR`"
        } else if (level >= 3) {
            typeCode := `"WARN`"
        }
        
        ; Call legacy method with translated parameters
        return this._legacyLogger.WriteLog(typeCode, message, A_Now)
    }
}

; USAGE - Client works with modern interface
legacySystem := LegacyLogger()
logger := LoggerAdapter(legacySystem)

; Client uses modern interface, adapter translates
output := logger.Log(`"User logged in`", 2)
MsgBox(output)
"
        }
        
        this.patternData["Structural_Bridge"] := {
            Name: "Bridge",
            Definition: "Decouples an abstraction from its implementation so that the two can vary independently. Separates 'what' from 'how'.",
            WhyHow: "WHY USE IT:`n• When you want to avoid permanent binding between abstraction and implementation`n• When both abstractions and implementations should be extensible`n• To prevent explosion of subclasses from combining variations`n• When implementation details should be hidden from clients`n`nHOW IT WORKS:`n• Abstraction holds a reference to an Implementor`n• Abstraction delegates implementation work to the Implementor`n• Both Abstraction and Implementor can have subclasses`n• Implementations can be switched at runtime",
            Code: "
; IMPLEMENTOR - the 'how' (message delivery mechanism)
class MessageSender {
    Send(content) {
        throw Error(`"Must implement Send`")
    }
}

class EmailSender extends MessageSender {
    _server := `"`"
    
    __New(smtpServer) {
        this._server := smtpServer
    }
    
    Send(content) {
        return `"EMAIL via `" . this._server . `": `" . content
    }
}

class SmsSender extends MessageSender {
    _gateway := `"`"
    
    __New(gateway) {
        this._gateway := gateway
    }
    
    Send(content) {
        return `"SMS via `" . this._gateway . `": `" . content
    }
}

; ABSTRACTION - the 'what' (message type)
class Message {
    _sender := `"`"      ; Reference to implementor
    _recipient := `"`"
    _content := `"`"
    
    __New(sender) {
        this._sender := sender  ; Bridge to implementation
    }
    
    SetRecipient(recipient) {
        this._recipient := recipient
        return this
    }
    
    SetContent(content) {
        this._content := content
        return this
    }
    
    Send() {
        return this._sender.Send(this.Format())
    }
    
    Format() {
        return `"To: `" . this._recipient . `" | `" . this._content
    }
}

; Refined Abstraction - adds features
class UrgentMessage extends Message {
    Format() {
        return `"🚨 URGENT | To: `" . this._recipient . `" | `" . this._content
    }
}

; USAGE - Mix and match abstractions with implementations
emailSender := EmailSender(`"smtp.example.com`")
smsSender := SmsSender(`"sms-gateway.com`")

; Same abstraction, different implementations
msg1 := Message(emailSender)
    .SetRecipient(`"user@example.com`")
    .SetContent(`"Hello!`")

msg2 := Message(smsSender)
    .SetRecipient(`"+1234567890`")
    .SetContent(`"Hello!`")

; Different abstraction, same implementation
urgentMsg := UrgentMessage(emailSender)
    .SetRecipient(`"admin@example.com`")
    .SetContent(`"Server down!`")

MsgBox(msg1.Send() . `"`n`" . msg2.Send() . `"`n`" . urgentMsg.Send())
"
        }
        
        this.patternData["Structural_Composite"] := {
            Name: "Composite",
            Definition: "Composes objects into tree structures to represent part-whole hierarchies. Composite lets clients treat individual objects and compositions of objects uniformly.",
            WhyHow: "WHY USE IT:`n• When you have tree-like structures (file systems, org charts, menus)`n• When you want to treat individual objects and groups the same way`n• To simplify client code that works with complex structures`n• When adding new component types shouldn't affect existing code`n`nHOW IT WORKS:`n• Component interface defines operations for both leaves and composites`n• Leaf implements Component for individual objects`n• Composite implements Component and contains child Components`n• Client uses Component interface, unaware if it's leaf or composite",
            Code: "
; COMPONENT - common interface for files and folders
class FileSystemItem {
    GetName() {
        throw Error(`"Must implement`")
    }
    
    GetSize() {
        throw Error(`"Must implement`")
    }
    
    Display(indent := 0) {
        throw Error(`"Must implement`")
    }
}

; LEAF - individual object (file)
class FileItem extends FileSystemItem {
    _name := `"`"
    _size := 0
    
    __New(name, size) {
        this._name := name
        this._size := size
    }
    
    GetName() {
        return this._name
    }
    
    GetSize() {
        return this._size
    }
    
    Display(indent := 0) {
        spaces := `"`"
        Loop indent {
            spaces .= `"  `"
        }
        return spaces . `"📄 `" . this._name . `" (`" . this._size . `" bytes)`"
    }
}

; COMPOSITE - container that holds children
class FolderItem extends FileSystemItem {
    _name := `"`"
    _children := []
    
    __New(name) {
        this._name := name
        this._children := []
    }
    
    ; Composite-specific methods
    Add(item) {
        this._children.Push(item)
        return this
    }
    
    GetName() {
        return this._name
    }
    
    ; Aggregates size from all children (recursive)
    GetSize() {
        total := 0
        for child in this._children {
            total += child.GetSize()
        }
        return total
    }
    
    Display(indent := 0) {
        spaces := `"`"
        Loop indent {
            spaces .= `"  `"
        }
        output := spaces . `"📁 `" . this._name . `"/ (`" . this.GetSize() . `" bytes)`n`"
        
        for child in this._children {
            output .= child.Display(indent + 1) . `"`n`"
        }
        return output
    }
}

; USAGE - Build tree structure
root := FolderItem(`"Documents`")
    .Add(FileItem(`"readme.txt`", 1024))
    .Add(FileItem(`"data.csv`", 2048))

images := FolderItem(`"Images`")
    .Add(FileItem(`"photo.jpg`", 5000))
    .Add(FileItem(`"icon.png`", 500))

root.Add(images)

; Client treats individual files and folders the same way
MsgBox(root.Display() . `"`nTotal: `" . root.GetSize() . `" bytes`")
"
        }
        
        this.patternData["Structural_Decorator"] := {
            Name: "Decorator",
            Definition: "Attaches additional responsibilities to an object dynamically. Decorators provide a flexible alternative to subclassing for extending functionality.",
            WhyHow: "WHY USE IT:`n• To add features to objects without affecting other objects of same class`n• When extension by subclassing is impractical`n• To combine features in different ways at runtime`n• For 'wrapping' objects with new behaviors`n`nHOW IT WORKS:`n• Decorator implements same interface as the object it decorates`n• Decorator holds a reference to a Component object`n• Decorator forwards requests to the component and adds behavior`n• Multiple decorators can wrap each other (chaining)",
            Code: "
; COMPONENT - base interface
class TextComponent {
    GetContent() {
        throw Error(`"Must implement`")
    }
}

; Concrete Component
class PlainText extends TextComponent {
    _text := `"`"
    
    __New(text) {
        this._text := text
    }
    
    GetContent() {
        return this._text
    }
}

; BASE DECORATOR - wraps a component
class TextDecorator extends TextComponent {
    _wrapped := `"`"
    
    __New(component) {
        this._wrapped := component
    }
    
    GetContent() {
        return this._wrapped.GetContent()
    }
}

; CONCRETE DECORATORS - each adds specific behavior
class BoldDecorator extends TextDecorator {
    GetContent() {
        return `"**`" . this._wrapped.GetContent() . `"**`"
    }
}

class ItalicDecorator extends TextDecorator {
    GetContent() {
        return `"_`" . this._wrapped.GetContent() . `"_`"
    }
}

class UppercaseDecorator extends TextDecorator {
    GetContent() {
        return StrUpper(this._wrapped.GetContent())
    }
}

class BorderDecorator extends TextDecorator {
    GetContent() {
        content := this._wrapped.GetContent()
        border := `"─`"
        Loop StrLen(content) + 2 {
            border .= `"─`"
        }
        return border . `"`n│ `" . content . `" │`n`" . border
    }
}

; USAGE - Stack decorators to combine features
plain := PlainText(`"Hello World`")
bold := BoldDecorator(plain)
boldItalic := ItalicDecorator(bold)
shouting := UppercaseDecorator(boldItalic)
boxed := BorderDecorator(PlainText(`"Boxed Text`"))

MsgBox(`"Plain: `" . plain.GetContent()
    . `"`nBold: `" . bold.GetContent()
    . `"`nBold+Italic: `" . boldItalic.GetContent()
    . `"`nUppercase+Bold+Italic: `" . shouting.GetContent()
    . `"`n`n`" . boxed.GetContent())
"
        }
        
        this.patternData["Structural_Facade"] := {
            Name: "Facade",
            Definition: "Provides a unified interface to a set of interfaces in a subsystem. Facade defines a higher-level interface that makes the subsystem easier to use.",
            WhyHow: "WHY USE IT:`n• To simplify a complex subsystem`n• To reduce coupling between clients and subsystem components`n• To provide a single entry point to a set of APIs`n• To hide implementation details from clients`n`nHOW IT WORKS:`n• Facade knows which subsystem classes handle which requests`n• Facade delegates client requests to appropriate subsystem objects`n• Clients only interact with the Facade, not subsystem directly`n• Subsystem classes remain accessible for advanced users",
            Code: "
; SUBSYSTEM CLASSES - complex internal components
class VideoFileReader {
    _path := `"`"
    
    Open(path) {
        this._path := path
        return `"Opened: `" . path
    }
    
    ReadFrame(frameNum) {
        return `"Frame `" . frameNum . `" data`"
    }
    
    Close() {
        return `"Closed: `" . this._path
    }
}

class AudioExtractor {
    Extract(videoPath) {
        return `"Audio extracted from `" . videoPath
    }
}

class VideoEncoder {
    _codec := `"`"
    
    SetCodec(codec) {
        this._codec := codec
    }
    
    Encode(frameData) {
        return `"Encoded with `" . this._codec
    }
}

class VideoFileWriter {
    Write(path, data) {
        return `"Written to `" . path
    }
}

; FACADE - simple interface to complex subsystem
class VideoConverterFacade {
    _reader := `"`"
    _audio := `"`"
    _encoder := `"`"
    _writer := `"`"
    
    __New() {
        this._reader := VideoFileReader()
        this._audio := AudioExtractor()
        this._encoder := VideoEncoder()
        this._writer := VideoFileWriter()
    }
    
    ; ONE SIMPLE METHOD hides all complexity
    ConvertVideo(inputPath, outputPath, format) {
        steps := []
        
        ; Step 1: Open input
        steps.Push(this._reader.Open(inputPath))
        
        ; Step 2: Extract audio
        steps.Push(this._audio.Extract(inputPath))
        
        ; Step 3: Set codec based on format
        codec := (format = `"mp4`") ? `"H.264`" : `"VP9`"
        this._encoder.SetCodec(codec)
        
        ; Step 4: Encode frames
        steps.Push(this._encoder.Encode(this._reader.ReadFrame(1)))
        
        ; Step 5: Write output
        steps.Push(this._writer.Write(outputPath, `"encoded_data`"))
        
        ; Step 6: Close
        steps.Push(this._reader.Close())
        
        return `"Conversion complete!`n`n`" . this.JoinSteps(steps)
    }
    
    JoinSteps(steps) {
        output := `"`"
        for step in steps {
            output .= `"• `" . step . `"`n`"
        }
        return output
    }
}

; USAGE - Client uses simple interface
converter := VideoConverterFacade()
result := converter.ConvertVideo(`"movie.avi`", `"movie.mp4`", `"mp4`")
MsgBox(result)
"
        }
        
        this.patternData["Structural_Flyweight"] := {
            Name: "Flyweight",
            Definition: "Uses sharing to support large numbers of fine-grained objects efficiently. Reduces memory by sharing common state between multiple objects.",
            WhyHow: "WHY USE IT:`n• When an application uses a large number of similar objects`n• When storage costs are high due to object quantity`n• When most object state can be made extrinsic`n• For text rendering, game particles, or any repeated elements`n`nHOW IT WORKS:`n• INTRINSIC state: Shared, stored in flyweight (character, font)`n• EXTRINSIC state: Varies, passed as parameters (position, color)`n• Factory ensures flyweights are shared (returns existing or creates new)`n• Client stores extrinsic state separately",
            Code: "
; FLYWEIGHT - stores only INTRINSIC (shared) state
class CharacterGlyph {
    Character := `"`"
    FontFamily := `"`"
    FontSize := 0
    
    __New(char, font, size) {
        this.Character := char
        this.FontFamily := font
        this.FontSize := size
    }
    
    ; EXTRINSIC state (x, y, color) passed as parameters
    Render(x, y, color) {
        return `"'`" . this.Character . `"' at (`" . x . `",`" . y . `") `"
            . this.FontFamily . `" `" . this.FontSize . `"pt `" . color
    }
}

; FLYWEIGHT FACTORY - ensures sharing
class GlyphFactory {
    static _pool := Map()
    static _requests := 0
    static _created := 0
    
    static GetGlyph(char, font, size) {
        GlyphFactory._requests++
        
        ; Create unique key for this combination
        key := char . `"|`" . font . `"|`" . size
        
        ; Return existing or create new
        if (!GlyphFactory._pool.Has(key)) {
            GlyphFactory._pool.Set(key, CharacterGlyph(char, font, size))
            GlyphFactory._created++
        }
        
        return GlyphFactory._pool.Get(key)
    }
    
    static GetStats() {
        return `"Requests: `" . GlyphFactory._requests 
            . `", Created: `" . GlyphFactory._created
            . `", Memory saved: `" . (GlyphFactory._requests - GlyphFactory._created) . `" objects`"
    }
}

; Client stores EXTRINSIC state
class CharacterContext {
    Glyph := `"`"
    X := 0
    Y := 0
    Color := `"Black`"
    
    __New(glyph, x, y, color) {
        this.Glyph := glyph
        this.X := x
        this.Y := y
        this.Color := color
    }
    
    Render() {
        return this.Glyph.Render(this.X, this.Y, this.Color)
    }
}

; USAGE - Render text 'HELLO' - only 4 unique glyphs needed
chars := []
text := `"HELLO`"

Loop Parse, text {
    glyph := GlyphFactory.GetGlyph(A_LoopField, `"Arial`", 12)
    chars.Push(CharacterContext(glyph, A_Index * 10, 100, `"Blue`"))
}

output := `"`"
for ctx in chars {
    output .= ctx.Render() . `"`n`"
}

MsgBox(output . `"`n`" . GlyphFactory.GetStats())
; H, E, L, O = 4 glyphs created, but L is reused (5 requests, 4 created)
"
        }
        
        this.patternData["Structural_Proxy"] := {
            Name: "Proxy",
            Definition: "Provides a surrogate or placeholder for another object to control access to it. The proxy controls when and how clients access the real object.",
            WhyHow: "WHY USE IT:`n• Virtual Proxy: Lazy initialization of expensive objects`n• Protection Proxy: Access control based on permissions`n• Remote Proxy: Local representative of remote object`n• Caching Proxy: Cache results to avoid repeated work`n`nHOW IT WORKS:`n• Proxy implements same interface as RealSubject`n• Proxy holds reference to RealSubject (may create lazily)`n• Proxy intercepts requests and adds control logic`n• Client works with Proxy as if it were the RealSubject",
            Code: "
; Subject interface
class Database {
    Query(sql) {
        throw Error(`"Must implement`")
    }
}

; Real Subject - expensive to create
class RealDatabase extends Database {
    _connectionString := `"`"
    _connected := false
    
    __New(connectionString) {
        this._connectionString := connectionString
        ; Simulate expensive connection
        Sleep(100)
        this._connected := true
    }
    
    Query(sql) {
        return `"Result from: `" . sql
    }
}

; VIRTUAL PROXY - lazy initialization
class LazyDatabaseProxy extends Database {
    _realDb := `"`"
    _connectionString := `"`"
    
    __New(connectionString) {
        ; Just store connection string - don't connect yet
        this._connectionString := connectionString
    }
    
    _EnsureConnected() {
        if (this._realDb = `"`") {
            this._realDb := RealDatabase(this._connectionString)
        }
    }
    
    Query(sql) {
        this._EnsureConnected()  ; Create real DB only when needed
        return this._realDb.Query(sql)
    }
    
    IsConnected() {
        return (this._realDb != `"`")
    }
}

; PROTECTION PROXY - access control
class SecureDatabaseProxy extends Database {
    _realDb := `"`"
    _userRole := `"`"
    
    __New(realDb, userRole) {
        this._realDb := realDb
        this._userRole := userRole
    }
    
    Query(sql) {
        ; Check permissions before allowing query
        if (InStr(sql, `"DELETE`") && this._userRole != `"admin`") {
            return `"ACCESS DENIED: Only admins can delete`"
        }
        if (InStr(sql, `"DROP`")) {
            return `"ACCESS DENIED: DROP not allowed`"
        }
        return this._realDb.Query(sql)
    }
}

; CACHING PROXY - cache results
class CachingDatabaseProxy extends Database {
    _realDb := `"`"
    _cache := Map()
    
    __New(realDb) {
        this._realDb := realDb
    }
    
    Query(sql) {
        if (this._cache.Has(sql)) {
            return `"[CACHED] `" . this._cache.Get(sql)
        }
        result := this._realDb.Query(sql)
        this._cache.Set(sql, result)
        return result
    }
}

; USAGE
lazyDb := LazyDatabaseProxy(`"server=localhost`")
MsgBox(`"Connected? `" . lazyDb.IsConnected())  ; false - not yet
result := lazyDb.Query(`"SELECT * FROM users`")  ; NOW it connects
MsgBox(`"Connected? `" . lazyDb.IsConnected() . `"`n`" . result)

realDb := RealDatabase(`"server=localhost`")
secureDb := SecureDatabaseProxy(realDb, `"user`")
MsgBox(secureDb.Query(`"DELETE FROM users`"))  ; ACCESS DENIED
"
        }
        
        ; ──────────────────────────────────────────────────────────────────────
        ; BEHAVIORAL PATTERNS
        ; ──────────────────────────────────────────────────────────────────────
        
        this.patternData["Behavioral_Chain of Responsibility"] := {
            Name: "Chain of Responsibility",
            Definition: "Avoids coupling the sender of a request to its receiver by giving more than one object a chance to handle the request. Chain the receiving objects and pass the request along until one handles it.",
            WhyHow: "WHY USE IT:`n• When more than one object may handle a request`n• When you want to issue a request without specifying the receiver`n• For event handling, logging levels, approval workflows`n• To decouple senders from receivers`n`nHOW IT WORKS:`n• Handler defines interface with Handle() and SetNext()`n• Each ConcreteHandler decides to process or pass to successor`n• Client sends request to first handler in chain`n• Request travels chain until handled or chain ends",
            Code: "
; Handler base class
class SupportHandler {
    _nextHandler := `"`"
    
    SetNext(handler) {
        this._nextHandler := handler
        return handler  ; Allow chaining: a.SetNext(b).SetNext(c)
    }
    
    Handle(ticket) {
        if (this._nextHandler != `"`") {
            return this._nextHandler.Handle(ticket)
        }
        return `"No handler available for this ticket`"
    }
}

; Support Ticket
class Ticket {
    Type := `"`"
    Priority := `"`"
    Description := `"`"
    
    __New(type, priority, description) {
        this.Type := type
        this.Priority := priority
        this.Description := description
    }
}

; Concrete Handlers
class FrontlineSupport extends SupportHandler {
    Handle(ticket) {
        ; Handle simple inquiries
        if (ticket.Type = `"inquiry`" && ticket.Priority = `"low`") {
            return `"FRONTLINE: Answered inquiry - `" . ticket.Description
        }
        return super.Handle(ticket)  ; Pass to next
    }
}

class TechnicalSupport extends SupportHandler {
    Handle(ticket) {
        if (ticket.Type = `"technical`") {
            return `"TECH SUPPORT: Resolved - `" . ticket.Description
        }
        return super.Handle(ticket)
    }
}

class BillingSupport extends SupportHandler {
    Handle(ticket) {
        if (ticket.Type = `"billing`") {
            return `"BILLING: Processed - `" . ticket.Description
        }
        return super.Handle(ticket)
    }
}

class ManagerEscalation extends SupportHandler {
    Handle(ticket) {
        if (ticket.Priority = `"critical`") {
            return `"MANAGER: Escalated critical issue - `" . ticket.Description
        }
        return super.Handle(ticket)
    }
}

; USAGE - Build the chain
frontline := FrontlineSupport()
tech := TechnicalSupport()
billing := BillingSupport()
manager := ManagerEscalation()

; Chain: frontline -> tech -> billing -> manager
frontline.SetNext(tech).SetNext(billing).SetNext(manager)

; Test different tickets
tickets := [
    Ticket(`"technical`", `"medium`", `"App crashes on startup`"),
    Ticket(`"billing`", `"low`", `"Invoice question`"),
    Ticket(`"other`", `"critical`", `"Data breach detected`"),
    Ticket(`"inquiry`", `"low`", `"How to reset password`")
]

output := `"`"
for t in tickets {
    output .= frontline.Handle(t) . `"`n`"
}
MsgBox(output)
"
        }
        
        this.patternData["Behavioral_Command"] := {
            Name: "Command",
            Definition: "Encapsulates a request as an object, thereby letting you parameterize clients with different requests, queue or log requests, and support undoable operations.",
            WhyHow: "WHY USE IT:`n• To parameterize objects with operations`n• To queue, schedule, or log operations`n• To implement undo/redo functionality`n• To structure a system around high-level operations`n`nHOW IT WORKS:`n• Command interface declares Execute() (and optionally Undo())`n• ConcreteCommand stores receiver and parameters`n• Invoker asks command to execute (manages history)`n• Receiver knows how to perform the actual work",
            Code: "
; RECEIVER - knows how to perform operations
class TextEditor {
    _text := `"`"
    _cursor := 0
    
    GetText() {
        return this._text
    }
    
    Insert(text) {
        before := SubStr(this._text, 1, this._cursor)
        after := SubStr(this._text, this._cursor + 1)
        this._text := before . text . after
        this._cursor += StrLen(text)
    }
    
    Delete(count) {
        if (this._cursor >= count) {
            before := SubStr(this._text, 1, this._cursor - count)
            after := SubStr(this._text, this._cursor + 1)
            this._text := before . after
            this._cursor -= count
        }
    }
}

; COMMAND INTERFACE
class Command {
    Execute() {
        throw Error(`"Must implement`")
    }
    Undo() {
        throw Error(`"Must implement`")
    }
}

; CONCRETE COMMANDS
class InsertCommand extends Command {
    _editor := `"`"
    _text := `"`"
    
    __New(editor, text) {
        this._editor := editor
        this._text := text
    }
    
    Execute() {
        this._editor.Insert(this._text)
        return `"Inserted: '`" . this._text . `"'`"
    }
    
    Undo() {
        this._editor.Delete(StrLen(this._text))
        return `"Undid insert`"
    }
}

class DeleteCommand extends Command {
    _editor := `"`"
    _count := 0
    _deleted := `"`"
    
    __New(editor, count) {
        this._editor := editor
        this._count := count
    }
    
    Execute() {
        text := this._editor.GetText()
        this._deleted := SubStr(text, -this._count)
        this._editor.Delete(this._count)
        return `"Deleted: '`" . this._deleted . `"'`"
    }
    
    Undo() {
        this._editor.Insert(this._deleted)
        return `"Restored: '`" . this._deleted . `"'`"
    }
}

; INVOKER - manages command execution and history
class CommandInvoker {
    _history := []
    _redoStack := []
    
    __New() {
        this._history := []
        this._redoStack := []
    }
    
    Execute(cmd) {
        result := cmd.Execute()
        this._history.Push(cmd)
        this._redoStack := []  ; Clear redo after new command
        return result
    }
    
    Undo() {
        if (this._history.Length = 0) {
            return `"Nothing to undo`"
        }
        cmd := this._history.Pop()
        result := cmd.Undo()
        this._redoStack.Push(cmd)
        return result
    }
    
    Redo() {
        if (this._redoStack.Length = 0) {
            return `"Nothing to redo`"
        }
        cmd := this._redoStack.Pop()
        result := cmd.Execute()
        this._history.Push(cmd)
        return result
    }
}

; USAGE
editor := TextEditor()
invoker := CommandInvoker()

output := `"`"
output .= invoker.Execute(InsertCommand(editor, `"Hello `")) . `"`n`"
output .= invoker.Execute(InsertCommand(editor, `"World!`")) . `"`n`"
output .= `"Text: '`" . editor.GetText() . `"'`n`"

output .= invoker.Undo() . `"`n`"
output .= `"After undo: '`" . editor.GetText() . `"'`n`"

output .= invoker.Redo() . `"`n`"
output .= `"After redo: '`" . editor.GetText() . `"'`"

MsgBox(output)
"
        }
        
        this.patternData["Behavioral_Interpreter"] := {
            Name: "Interpreter",
            Definition: "Given a language, defines a representation for its grammar along with an interpreter that uses the representation to interpret sentences in the language.",
            WhyHow: "WHY USE IT:`n• When you have a simple language to interpret`n• For expression parsing (math, search queries, configs)`n• When grammar is simple and efficiency isn't critical`n• To implement domain-specific languages (DSLs)`n`nHOW IT WORKS:`n• Abstract Expression defines Interpret() interface`n• Terminal Expressions: atomic values (numbers, variables)`n• Non-terminal Expressions: combine other expressions (add, multiply)`n• Context contains global information (variable values)",
            Code: "
; EXPRESSION INTERFACE
class Expression {
    Interpret(context) {
        throw Error(`"Must implement`")
    }
}

; TERMINAL EXPRESSIONS - leaf nodes
class NumberExpr extends Expression {
    _value := 0
    
    __New(value) {
        this._value := value
    }
    
    Interpret(context) {
        return this._value
    }
}

class VariableExpr extends Expression {
    _name := `"`"
    
    __New(name) {
        this._name := name
    }
    
    Interpret(context) {
        if (context.Has(this._name)) {
            return context.Get(this._name)
        }
        return 0
    }
}

; NON-TERMINAL EXPRESSIONS - combine other expressions
class AddExpr extends Expression {
    _left := `"`"
    _right := `"`"
    
    __New(left, right) {
        this._left := left
        this._right := right
    }
    
    Interpret(context) {
        return this._left.Interpret(context) + this._right.Interpret(context)
    }
}

class SubtractExpr extends Expression {
    _left := `"`"
    _right := `"`"
    
    __New(left, right) {
        this._left := left
        this._right := right
    }
    
    Interpret(context) {
        return this._left.Interpret(context) - this._right.Interpret(context)
    }
}

class MultiplyExpr extends Expression {
    _left := `"`"
    _right := `"`"
    
    __New(left, right) {
        this._left := left
        this._right := right
    }
    
    Interpret(context) {
        return this._left.Interpret(context) * this._right.Interpret(context)
    }
}

; USAGE - Build expression tree for: (x + 5) * (y - 2)
; Where x=10, y=7
context := Map(`"x`", 10, `"y`", 7)

; (x + 5) = 15
addExpr := AddExpr(VariableExpr(`"x`"), NumberExpr(5))

; (y - 2) = 5
subExpr := SubtractExpr(VariableExpr(`"y`"), NumberExpr(2))

; (x + 5) * (y - 2) = 15 * 5 = 75
fullExpr := MultiplyExpr(addExpr, subExpr)

result := fullExpr.Interpret(context)
MsgBox(`"Expression: (x + 5) * (y - 2)`n`"
    . `"Where x=`" . context.Get(`"x`") . `", y=`" . context.Get(`"y`") . `"`n`"
    . `"Result: `" . result)
"
        }
        
        this.patternData["Behavioral_Iterator"] := {
            Name: "Iterator",
            Definition: "Provides a way to access the elements of an aggregate object sequentially without exposing its underlying representation.",
            WhyHow: "WHY USE IT:`n• To traverse collections without exposing internal structure`n• To support multiple traversal algorithms for same collection`n• To provide uniform interface for iterating different structures`n• To separate traversal logic from collection logic`n`nHOW IT WORKS:`n• Iterator interface: HasNext(), Next(), Reset()`n• Aggregate interface: CreateIterator()`n• ConcreteIterator tracks position and traverses ConcreteAggregate`n• Multiple iterators can traverse same collection simultaneously",
            Code: "
; AGGREGATE - collection that creates iterators
class BookCollection {
    _books := []
    
    __New() {
        this._books := []
    }
    
    Add(title, author) {
        this._books.Push({Title: title, Author: author})
    }
    
    GetAt(index) {
        if (index >= 1 && index <= this._books.Length) {
            return this._books[index]
        }
        return `"`"
    }
    
    GetCount() {
        return this._books.Length
    }
    
    ; Factory method for creating iterators
    CreateIterator() {
        return BookIterator(this)
    }
    
    CreateReverseIterator() {
        return ReverseBookIterator(this)
    }
}

; FORWARD ITERATOR
class BookIterator {
    _collection := `"`"
    _position := 1
    
    __New(collection) {
        this._collection := collection
        this._position := 1
    }
    
    HasNext() {
        return this._position <= this._collection.GetCount()
    }
    
    Next() {
        if (!this.HasNext()) {
            throw Error(`"No more elements`")
        }
        item := this._collection.GetAt(this._position)
        this._position++
        return item
    }
    
    Reset() {
        this._position := 1
    }
}

; REVERSE ITERATOR - different traversal of same collection
class ReverseBookIterator {
    _collection := `"`"
    _position := 0
    
    __New(collection) {
        this._collection := collection
        this._position := collection.GetCount()
    }
    
    HasNext() {
        return this._position >= 1
    }
    
    Next() {
        if (!this.HasNext()) {
            throw Error(`"No more elements`")
        }
        item := this._collection.GetAt(this._position)
        this._position--
        return item
    }
    
    Reset() {
        this._position := this._collection.GetCount()
    }
}

; USAGE
library := BookCollection()
library.Add(`"Design Patterns`", `"GoF`")
library.Add(`"Clean Code`", `"Robert Martin`")
library.Add(`"Refactoring`", `"Martin Fowler`")

; Forward iteration
output := `"Forward:`n`"
iter := library.CreateIterator()
while (iter.HasNext()) {
    book := iter.Next()
    output .= `"  `" . book.Title . `" by `" . book.Author . `"`n`"
}

; Reverse iteration
output .= `"`nReverse:`n`"
revIter := library.CreateReverseIterator()
while (revIter.HasNext()) {
    book := revIter.Next()
    output .= `"  `" . book.Title . `" by `" . book.Author . `"`n`"
}

MsgBox(output)
"
        }
        
        this.patternData["Behavioral_Mediator"] := {
            Name: "Mediator",
            Definition: "Defines an object that encapsulates how a set of objects interact. Mediator promotes loose coupling by keeping objects from referring to each other explicitly.",
            WhyHow: "WHY USE IT:`n• When many objects communicate in complex ways`n• To reduce chaotic dependencies between objects`n• For chat rooms, air traffic control, GUI components`n• When you want to centralize complex communications`n`nHOW IT WORKS:`n• Mediator interface defines communication method`n• Colleagues know their Mediator (not each other)`n• Colleagues send messages through Mediator`n• Mediator routes messages to appropriate recipients",
            Code: "
; MEDIATOR
class ChatRoom {
    _participants := []
    _history := []
    
    __New() {
        this._participants := []
        this._history := []
    }
    
    Register(participant) {
        this._participants.Push(participant)
        participant.SetChatRoom(this)
    }
    
    ; Central communication method
    SendMessage(message, sender, recipient := `"`") {
        this._history.Push({
            From: sender.GetName(),
            To: recipient != `"`" ? recipient.GetName() : `"ALL`",
            Message: message
        })
        
        for p in this._participants {
            if (p != sender) {
                if (recipient = `"`" || p = recipient) {
                    p.Receive(message, sender.GetName())
                }
            }
        }
    }
    
    GetHistory() {
        output := `"Chat History:`n`"
        for entry in this._history {
            output .= entry.From . `" -> `" . entry.To . `": `" . entry.Message . `"`n`"
        }
        return output
    }
}

; COLLEAGUE - communicates through mediator
class ChatUser {
    _name := `"`"
    _chatRoom := `"`"
    _inbox := []
    
    __New(name) {
        this._name := name
        this._inbox := []
    }
    
    SetChatRoom(room) {
        this._chatRoom := room
    }
    
    GetName() {
        return this._name
    }
    
    ; Send through mediator, not directly
    Send(message, recipient := `"`") {
        this._chatRoom.SendMessage(message, this, recipient)
    }
    
    Receive(message, senderName) {
        this._inbox.Push({From: senderName, Message: message})
    }
    
    GetInbox() {
        output := this._name . `"'s Inbox:`n`"
        for msg in this._inbox {
            output .= `"  From `" . msg.From . `": `" . msg.Message . `"`n`"
        }
        return output
    }
}

; USAGE
chatRoom := ChatRoom()

alice := ChatUser(`"Alice`")
bob := ChatUser(`"Bob`")
charlie := ChatUser(`"Charlie`")

chatRoom.Register(alice)
chatRoom.Register(bob)
chatRoom.Register(charlie)

; All communication goes through mediator
alice.Send(`"Hello everyone!`")           ; Broadcast
bob.Send(`"Hi Alice!`", alice)            ; Direct message
charlie.Send(`"Hey team`")                 ; Broadcast

output := chatRoom.GetHistory() . `"`n`"
output .= alice.GetInbox() . `"`n`"
output .= bob.GetInbox()

MsgBox(output)
"
        }
        
        this.patternData["Behavioral_Memento"] := {
            Name: "Memento",
            Definition: "Without violating encapsulation, captures and externalizes an object's internal state so that the object can be restored to this state later.",
            WhyHow: "WHY USE IT:`n• To implement save/restore functionality (undo, checkpoints)`n• To snapshot object state for later recovery`n• To preserve encapsulation while allowing state capture`n• For save games, transaction rollback, history`n`nHOW IT WORKS:`n• Originator: Creates memento with current state, restores from memento`n• Memento: Stores Originator's internal state (opaque to others)`n• Caretaker: Requests mementos, stores them, passes back for restore`n• Caretaker never examines memento contents",
            Code: "
; MEMENTO - stores state snapshot (immutable)
class GameMemento {
    _playerName := `"`"
    _level := 0
    _score := 0
    _health := 0
    _savedAt := `"`"
    
    __New(playerName, level, score, health) {
        this._playerName := playerName
        this._level := level
        this._score := score
        this._health := health
        this._savedAt := A_Now
    }
    
    ; Only Originator should access these
    GetPlayerName() {
        return this._playerName
    }
    GetLevel() {
        return this._level
    }
    GetScore() {
        return this._score
    }
    GetHealth() {
        return this._health
    }
    
    ; Public description for Caretaker
    GetDescription() {
        return `"Level `" . this._level . `" | Score: `" . this._score . `" | `" . this._savedAt
    }
}

; ORIGINATOR - creates and restores from mementos
class Game {
    _playerName := `"`"
    _level := 1
    _score := 0
    _health := 100
    
    __New(playerName) {
        this._playerName := playerName
    }
    
    Play() {
        this._level++
        this._score += Random(50, 200)
        this._health -= Random(5, 20)
        if (this._health < 0) {
            this._health := 0
        }
    }
    
    ; Create memento of current state
    Save() {
        return GameMemento(this._playerName, this._level, this._score, this._health)
    }
    
    ; Restore from memento
    Load(memento) {
        this._playerName := memento.GetPlayerName()
        this._level := memento.GetLevel()
        this._score := memento.GetScore()
        this._health := memento.GetHealth()
    }
    
    GetStatus() {
        return this._playerName . `" | Level: `" . this._level 
            . `" | Score: `" . this._score . `" | Health: `" . this._health
    }
}

; CARETAKER - manages mementos
class SaveManager {
    _saves := Map()
    _autoSaves := []
    
    __New() {
        this._autoSaves := []
    }
    
    SaveToSlot(slotNum, memento) {
        this._saves.Set(slotNum, memento)
    }
    
    LoadFromSlot(slotNum) {
        if (this._saves.Has(slotNum)) {
            return this._saves.Get(slotNum)
        }
        return `"`"
    }
    
    AutoSave(memento) {
        this._autoSaves.Push(memento)
        if (this._autoSaves.Length > 3) {
            this._autoSaves.RemoveAt(1)  ; Keep only last 3
        }
    }
    
    GetLatestAutoSave() {
        if (this._autoSaves.Length > 0) {
            return this._autoSaves[this._autoSaves.Length]
        }
        return `"`"
    }
}

; USAGE
game := Game(`"Hero`")
saveManager := SaveManager()

output := `"Starting: `" . game.GetStatus() . `"`n`"

; Play and auto-save
game.Play()
saveManager.AutoSave(game.Save())
output .= `"After play: `" . game.GetStatus() . `"`n`"

; Manual save to slot 1
saveManager.SaveToSlot(1, game.Save())
output .= `"Saved to slot 1`n`"

; Play more (might die!)
game.Play()
game.Play()
output .= `"After more play: `" . game.GetStatus() . `"`n`"

; Load from slot 1
memento := saveManager.LoadFromSlot(1)
game.Load(memento)
output .= `"After load: `" . game.GetStatus()

MsgBox(output)
"
        }
        
        this.patternData["Behavioral_Observer"] := {
            Name: "Observer",
            Definition: "Defines a one-to-many dependency between objects so that when one object changes state, all its dependents are notified and updated automatically.",
            WhyHow: "WHY USE IT:`n• When change in one object requires changing others`n• When an object should notify unknown number of objects`n• For event handling, data binding, MVC architecture`n• To maintain consistency between related objects`n`nHOW IT WORKS:`n• Subject maintains list of Observers`n• Subject provides Attach/Detach/Notify methods`n• Observers implement Update() method`n• On state change, Subject calls Notify() which updates all Observers",
            Code: "
; SUBJECT - the object being observed
class Stock {
    _symbol := `"`"
    _price := 0.0
    _observers := []
    
    __New(symbol, initialPrice) {
        this._symbol := symbol
        this._price := initialPrice
        this._observers := []
    }
    
    Attach(observer) {
        this._observers.Push(observer)
    }
    
    Detach(observer) {
        newList := []
        for obs in this._observers {
            if (obs != observer) {
                newList.Push(obs)
            }
        }
        this._observers := newList
    }
    
    Notify() {
        for observer in this._observers {
            observer.Update(this)
        }
    }
    
    SetPrice(newPrice) {
        oldPrice := this._price
        this._price := newPrice
        this.Notify()  ; Notify all observers of change
    }
    
    GetSymbol() {
        return this._symbol
    }
    
    GetPrice() {
        return this._price
    }
}

; OBSERVER - reacts to subject changes
class PriceDisplay {
    _name := `"`"
    _lastPrice := 0
    
    __New(name) {
        this._name := name
    }
    
    Update(stock) {
        this._lastPrice := stock.GetPrice()
    }
    
    GetDisplay() {
        return this._name . `": $`" . Format(`"{:.2f}`", this._lastPrice)
    }
}

class PriceAlert {
    _threshold := 0
    _alerts := []
    
    __New(threshold) {
        this._threshold := threshold
        this._alerts := []
    }
    
    Update(stock) {
        if (stock.GetPrice() > this._threshold) {
            this._alerts.Push(stock.GetSymbol() . `" exceeded $`" . this._threshold)
        }
    }
    
    GetAlerts() {
        return this._alerts
    }
}

class TradeLogger {
    _log := []
    
    __New() {
        this._log := []
    }
    
    Update(stock) {
        this._log.Push(A_Now . `": `" . stock.GetSymbol() . `" = $`" . stock.GetPrice())
    }
    
    GetLog() {
        return this._log
    }
}

; USAGE
apple := Stock(`"AAPL`", 150.00)

display := PriceDisplay(`"Main Display`")
alert := PriceAlert(155)
logger := TradeLogger()

; Attach observers
apple.Attach(display)
apple.Attach(alert)
apple.Attach(logger)

; Price changes notify all observers
apple.SetPrice(152.50)
apple.SetPrice(158.00)  ; Triggers alert
apple.SetPrice(160.25)

output := display.GetDisplay() . `"`n`n`"
output .= `"Alerts:`n`"
for a in alert.GetAlerts() {
    output .= `"  `" . a . `"`n`"
}
output .= `"`nLog:`n`"
for entry in logger.GetLog() {
    output .= `"  `" . entry . `"`n`"
}

MsgBox(output)
"
        }
        
        this.patternData["Behavioral_State"] := {
            Name: "State",
            Definition: "Allows an object to alter its behavior when its internal state changes. The object will appear to change its class.",
            WhyHow: "WHY USE IT:`n• When behavior depends on state and changes at runtime`n• When operations have large conditional statements based on state`n• For state machines (orders, workflows, game characters)`n• To localize state-specific behavior and partition by state`n`nHOW IT WORKS:`n• Context holds reference to current State object`n• State interface defines methods for state-specific behavior`n• ConcreteStates implement behavior and handle transitions`n• Context delegates behavior to current State",
            Code: "
; STATE INTERFACE
class OrderState {
    HandlePay(order) {
        throw Error(`"Must implement`")
    }
    HandleShip(order) {
        throw Error(`"Must implement`")
    }
    HandleDeliver(order) {
        throw Error(`"Must implement`")
    }
    HandleCancel(order) {
        throw Error(`"Must implement`")
    }
    GetName() {
        throw Error(`"Must implement`")
    }
}

; CONCRETE STATES
class PendingState extends OrderState {
    HandlePay(order) {
        order.SetState(PaidState())
        return `"✓ Payment processed`"
    }
    HandleShip(order) {
        return `"✗ Cannot ship: Not paid`"
    }
    HandleDeliver(order) {
        return `"✗ Cannot deliver: Not shipped`"
    }
    HandleCancel(order) {
        order.SetState(CancelledState())
        return `"✓ Order cancelled`"
    }
    GetName() {
        return `"Pending Payment`"
    }
}

class PaidState extends OrderState {
    HandlePay(order) {
        return `"✗ Already paid`"
    }
    HandleShip(order) {
        order.SetState(ShippedState())
        return `"✓ Order shipped`"
    }
    HandleDeliver(order) {
        return `"✗ Cannot deliver: Not shipped`"
    }
    HandleCancel(order) {
        order.SetState(CancelledState())
        return `"✓ Cancelled, refund initiated`"
    }
    GetName() {
        return `"Paid`"
    }
}

class ShippedState extends OrderState {
    HandlePay(order) {
        return `"✗ Already paid`"
    }
    HandleShip(order) {
        return `"✗ Already shipped`"
    }
    HandleDeliver(order) {
        order.SetState(DeliveredState())
        return `"✓ Order delivered`"
    }
    HandleCancel(order) {
        return `"✗ Cannot cancel: In transit`"
    }
    GetName() {
        return `"Shipped`"
    }
}

class DeliveredState extends OrderState {
    HandlePay(order) {
        return `"✗ Order complete`"
    }
    HandleShip(order) {
        return `"✗ Order complete`"
    }
    HandleDeliver(order) {
        return `"✗ Already delivered`"
    }
    HandleCancel(order) {
        return `"✗ Cannot cancel: Delivered`"
    }
    GetName() {
        return `"Delivered`"
    }
}

class CancelledState extends OrderState {
    HandlePay(order) {
        return `"✗ Order cancelled`"
    }
    HandleShip(order) {
        return `"✗ Order cancelled`"
    }
    HandleDeliver(order) {
        return `"✗ Order cancelled`"
    }
    HandleCancel(order) {
        return `"✗ Already cancelled`"
    }
    GetName() {
        return `"Cancelled`"
    }
}

; CONTEXT - delegates to current state
class Order {
    _id := `"`"
    _state := `"`"
    
    __New(id) {
        this._id := id
        this._state := PendingState()
    }
    
    SetState(newState) {
        this._state := newState
    }
    
    ; Delegate all actions to current state
    Pay() {
        return this._state.HandlePay(this)
    }
    Ship() {
        return this._state.HandleShip(this)
    }
    Deliver() {
        return this._state.HandleDeliver(this)
    }
    Cancel() {
        return this._state.HandleCancel(this)
    }
    
    GetStatus() {
        return `"Order `" . this._id . `": `" . this._state.GetName()
    }
}

; USAGE - State determines behavior
order := Order(`"ORD-001`")
output := order.GetStatus() . `"`n`"

output .= order.Ship() . `"`n`"        ; Can't ship - not paid
output .= order.Pay() . `"`n`"         ; Success
output .= order.GetStatus() . `"`n`"

output .= order.Ship() . `"`n`"        ; Success
output .= order.GetStatus() . `"`n`"

output .= order.Cancel() . `"`n`"      ; Can't cancel - shipped
output .= order.Deliver() . `"`n`"     ; Success
output .= order.GetStatus()

MsgBox(output)
"
        }
        
        this.patternData["Behavioral_Strategy"] := {
            Name: "Strategy",
            Definition: "Defines a family of algorithms, encapsulates each one, and makes them interchangeable. Strategy lets the algorithm vary independently from clients that use it.",
            WhyHow: "WHY USE IT:`n• When you need different variants of an algorithm`n• To avoid exposing complex algorithm structures`n• When algorithm selection should happen at runtime`n• To eliminate conditional statements for selecting behavior`n`nHOW IT WORKS:`n• Strategy interface declares algorithm method`n• ConcreteStrategies implement the algorithm differently`n• Context holds a Strategy reference`n• Client sets Strategy; Context uses it without knowing details",
            Code: "
; STRATEGY INTERFACE
class PaymentStrategy {
    Pay(amount) {
        throw Error(`"Must implement Pay`")
    }
    GetName() {
        throw Error(`"Must implement GetName`")
    }
}

; CONCRETE STRATEGIES
class CreditCardStrategy extends PaymentStrategy {
    _cardNumber := `"`"
    _name := `"`"
    
    __New(cardNumber, name) {
        ; Mask card number for security
        this._cardNumber := `"****-****-****-`" . SubStr(cardNumber, -4)
        this._name := name
    }
    
    Pay(amount) {
        return `"Charged $`" . Format(`"{:.2f}`", amount) . `" to `" . this._cardNumber
    }
    
    GetName() {
        return `"Credit Card`"
    }
}

class PayPalStrategy extends PaymentStrategy {
    _email := `"`"
    
    __New(email) {
        this._email := email
    }
    
    Pay(amount) {
        return `"PayPal payment of $`" . Format(`"{:.2f}`", amount) . `" from `" . this._email
    }
    
    GetName() {
        return `"PayPal`"
    }
}

class CryptoStrategy extends PaymentStrategy {
    _walletAddress := `"`"
    _currency := `"`"
    
    __New(wallet, currency := `"BTC`") {
        this._walletAddress := SubStr(wallet, 1, 8) . `"...`"
        this._currency := currency
    }
    
    Pay(amount) {
        ; Simulate conversion rate
        cryptoAmount := amount / 45000
        return `"Sent `" . Format(`"{:.6f}`", cryptoAmount) . `" `" . this._currency 
            . `" from `" . this._walletAddress
    }
    
    GetName() {
        return `"Crypto (`" . this._currency . `")`"
    }
}

; CONTEXT - uses strategy
class PaymentProcessor {
    _strategy := `"`"
    _history := []
    
    __New() {
        this._history := []
    }
    
    SetStrategy(strategy) {
        this._strategy := strategy
    }
    
    Checkout(amount) {
        if (this._strategy = `"`") {
            return `"Error: No payment method selected`"
        }
        
        result := this._strategy.Pay(amount)
        this._history.Push({
            Method: this._strategy.GetName(),
            Amount: amount,
            Result: result
        })
        return result
    }
    
    GetHistory() {
        output := `"Payment History:`n`"
        for entry in this._history {
            output .= `"  `" . entry.Method . `": $`" . entry.Amount . `"`n`"
        }
        return output
    }
}

; USAGE - Switch strategies at runtime
processor := PaymentProcessor()

; Pay with credit card
processor.SetStrategy(CreditCardStrategy(`"4111111111111234`", `"John Doe`"))
output := processor.Checkout(99.99) . `"`n`"

; Switch to PayPal
processor.SetStrategy(PayPalStrategy(`"john@example.com`"))
output .= processor.Checkout(49.99) . `"`n`"

; Switch to Crypto
processor.SetStrategy(CryptoStrategy(`"1A2B3C4D5E6F7G8H`", `"BTC`"))
output .= processor.Checkout(199.99) . `"`n`n`"

output .= processor.GetHistory()

MsgBox(output)
"
        }
        
        this.patternData["Behavioral_Template Method"] := {
            Name: "Template Method",
            Definition: "Defines the skeleton of an algorithm in an operation, deferring some steps to subclasses. Template Method lets subclasses redefine certain steps of an algorithm without changing the algorithm's structure.",
            WhyHow: "WHY USE IT:`n• When you have an algorithm with invariant parts and customizable parts`n• To control which parts subclasses can override`n• To avoid code duplication in similar algorithms`n• To implement the 'Don't call us, we'll call you' principle`n`nHOW IT WORKS:`n• Abstract class defines template method with algorithm skeleton`n• Template method calls abstract/hook methods`n• Abstract methods: MUST be overridden by subclasses`n• Hook methods: CAN be overridden (have default implementation)",
            Code: "
; ABSTRACT CLASS with Template Method
class DataProcessor {
    ; THE TEMPLATE METHOD - defines algorithm skeleton
    ; This method is final (shouldn't be overridden)
    Process() {
        output := `"Processing started...`n`"
        
        ; Step 1: Load (abstract - must override)
        output .= `"Loading: `"
        data := this.LoadData()
        output .= `"Done`n`"
        
        ; Step 2: Validate (hook - can override)
        output .= `"Validating: `"
        if (!this.ValidateData(data)) {
            return output . `"FAILED`n`"
        }
        output .= `"Passed`n`"
        
        ; Step 3: Transform (abstract - must override)
        output .= `"Transforming: `"
        transformed := this.TransformData(data)
        output .= `"Done`n`"
        
        ; Step 4: Post-process (hook - can override)
        output .= `"Post-processing: `"
        this.PostProcess(transformed)
        output .= `"Done`n`"
        
        ; Step 5: Save (abstract - must override)
        output .= `"Saving: `"
        this.SaveData(transformed)
        output .= `"Done`n`"
        
        return output . `"Processing complete!`"
    }
    
    ; ABSTRACT METHODS - subclasses MUST implement
    LoadData() {
        throw Error(`"Subclass must implement LoadData`")
    }
    
    TransformData(data) {
        throw Error(`"Subclass must implement TransformData`")
    }
    
    SaveData(data) {
        throw Error(`"Subclass must implement SaveData`")
    }
    
    ; HOOK METHODS - subclasses CAN override (have defaults)
    ValidateData(data) {
        return (data != `"`")  ; Default: just check not empty
    }
    
    PostProcess(data) {
        ; Default: do nothing
    }
}

; CONCRETE CLASS - implements abstract methods
class CsvProcessor extends DataProcessor {
    _inputPath := `"`"
    _outputPath := `"`"
    _rowCount := 0
    
    __New(input, output) {
        this._inputPath := input
        this._outputPath := output
    }
    
    LoadData() {
        ; Simulate loading CSV
        return `"Name,Age`nAlice,30`nBob,25`"
    }
    
    TransformData(data) {
        ; Convert to uppercase
        return StrUpper(data)
    }
    
    SaveData(data) {
        ; Simulate saving
        this._rowCount := StrSplit(data, `"`n`").Length
    }
    
    ; Override hook to add custom validation
    ValidateData(data) {
        return InStr(data, `",`")  ; Must contain comma (CSV format)
    }
    
    ; Override hook to add custom post-processing
    PostProcess(data) {
        ; Count rows processed
    }
}

class JsonProcessor extends DataProcessor {
    LoadData() {
        return `"{``"name``": ``"Test``"}`"
    }
    
    TransformData(data) {
        return StrReplace(data, `"Test`", `"Processed`")
    }
    
    SaveData(data) {
        ; Simulate saving JSON
    }
    
    ; Custom validation for JSON
    ValidateData(data) {
        return InStr(data, `"{`") && InStr(data, `"}`")
    }
}

; USAGE
csvProcessor := CsvProcessor(`"input.csv`", `"output.csv`")
jsonProcessor := JsonProcessor()

output := `"=== CSV Processing ===`n`"
output .= csvProcessor.Process() . `"`n`n`"

output .= `"=== JSON Processing ===`n`"
output .= jsonProcessor.Process()

MsgBox(output)
"
        }
        
        this.patternData["Behavioral_Visitor"] := {
            Name: "Visitor",
            Definition: "Represents an operation to be performed on the elements of an object structure. Visitor lets you define a new operation without changing the classes of the elements on which it operates.",
            WhyHow: "WHY USE IT:`n• To add new operations without modifying element classes`n• When many distinct operations need to be performed on objects`n• When element class hierarchy is stable but operations change often`n• For compilers, report generators, serializers`n`nHOW IT WORKS:`n• Visitor interface declares Visit method for each element type`n• Elements have Accept(visitor) that calls visitor.Visit(this)`n• This 'double dispatch' selects operation based on both types`n• New operations = new Visitors, not element changes",
            Code: "
; ELEMENT INTERFACE
class Employee {
    Accept(visitor) {
        throw Error(`"Must implement Accept`")
    }
}

; CONCRETE ELEMENTS
class Engineer extends Employee {
    Name := `"`"
    BaseSalary := 0
    Languages := []
    YearsExp := 0
    
    __New(name, salary, languages, years) {
        this.Name := name
        this.BaseSalary := salary
        this.Languages := languages
        this.YearsExp := years
    }
    
    ; Double dispatch: calls visitor's method for Engineer
    Accept(visitor) {
        return visitor.VisitEngineer(this)
    }
}

class Manager extends Employee {
    Name := `"`"
    BaseSalary := 0
    TeamSize := 0
    Department := `"`"
    
    __New(name, salary, teamSize, dept) {
        this.Name := name
        this.BaseSalary := salary
        this.TeamSize := teamSize
        this.Department := dept
    }
    
    Accept(visitor) {
        return visitor.VisitManager(this)
    }
}

class Executive extends Employee {
    Name := `"`"
    BaseSalary := 0
    StockOptions := 0
    
    __New(name, salary, options) {
        this.Name := name
        this.BaseSalary := salary
        this.StockOptions := options
    }
    
    Accept(visitor) {
        return visitor.VisitExecutive(this)
    }
}

; VISITOR INTERFACE
class EmployeeVisitor {
    VisitEngineer(eng) {
        throw Error(`"Must implement`")
    }
    VisitManager(mgr) {
        throw Error(`"Must implement`")
    }
    VisitExecutive(exec) {
        throw Error(`"Must implement`")
    }
}

; CONCRETE VISITORS - different operations on same structure
class SalaryCalculator extends EmployeeVisitor {
    _total := 0
    
    VisitEngineer(eng) {
        ; Engineers: base + experience bonus + language bonus
        salary := eng.BaseSalary
        salary += eng.BaseSalary * (eng.YearsExp * 0.02)
        salary += eng.Languages.Length * 1000
        this._total += salary
        return Format(`"{:.0f}`", salary)
    }
    
    VisitManager(mgr) {
        ; Managers: base + team size bonus
        salary := mgr.BaseSalary + (mgr.TeamSize * 500)
        this._total += salary
        return Format(`"{:.0f}`", salary)
    }
    
    VisitExecutive(exec) {
        ; Executives: base + stock options value
        salary := exec.BaseSalary + (exec.StockOptions * 50)
        this._total += salary
        return Format(`"{:.0f}`", salary)
    }
    
    GetTotal() {
        return this._total
    }
}

class ReportGenerator extends EmployeeVisitor {
    _report := `"`"
    
    VisitEngineer(eng) {
        this._report .= `"👨‍💻 `" . eng.Name . `" (Engineer)`n`"
        this._report .= `"   Skills: `" . this.JoinArray(eng.Languages) . `"`n`"
        this._report .= `"   Experience: `" . eng.YearsExp . `" years`n`n`"
    }
    
    VisitManager(mgr) {
        this._report .= `"👔 `" . mgr.Name . `" (Manager)`n`"
        this._report .= `"   Department: `" . mgr.Department . `"`n`"
        this._report .= `"   Team Size: `" . mgr.TeamSize . `"`n`n`"
    }
    
    VisitExecutive(exec) {
        this._report .= `"🎯 `" . exec.Name . `" (Executive)`n`"
        this._report .= `"   Stock Options: `" . exec.StockOptions . `"`n`n`"
    }
    
    JoinArray(arr) {
        result := `"`"
        for item in arr {
            result .= (result ? `", `" : `"`") . item
        }
        return result
    }
    
    GetReport() {
        return this._report
    }
}

; USAGE
employees := [
    Engineer(`"Alice`", 80000, [`"Python`", `"Java`", `"Go`"], 5),
    Engineer(`"Bob`", 75000, [`"JavaScript`"], 2),
    Manager(`"Carol`", 95000, 8, `"Engineering`"),
    Executive(`"Dave`", 150000, 10000)
]

; Calculate salaries
salaryCalc := SalaryCalculator()
output := `"=== Salary Calculation ===`n`"
for emp in employees {
    salary := emp.Accept(salaryCalc)
    output .= emp.Name . `": $`" . salary . `"`n`"
}
output .= `"Total: $`" . Format(`"{:.0f}`", salaryCalc.GetTotal()) . `"`n`n`"

; Generate report
reportGen := ReportGenerator()
for emp in employees {
    emp.Accept(reportGen)
}
output .= `"=== Employee Report ===`n`" . reportGen.GetReport()

MsgBox(output)
"
        }
        
        ; ──────────────────────────────────────────────────────────────────────
        ; ARCHITECTURAL PATTERNS
        ; ──────────────────────────────────────────────────────────────────────
        
        this.patternData["Architecture_Dependency Injection"] := {
            Name: "Dependency Injection",
            Definition: "A technique where an object receives its dependencies from an external source rather than creating them itself. Implements Inversion of Control (IoC).",
            WhyHow: "WHY USE IT:`n• To decouple classes from their dependencies`n• To make code more testable (can inject mocks)`n• To enable runtime configuration of dependencies`n• To centralize object creation logic`n`nHOW IT WORKS:`n• Classes declare dependencies in constructors or setters`n• A 'container' or 'injector' creates and wires objects`n• Dependencies are passed IN, not created internally`n• Classes depend on interfaces, not concrete implementations",
            Code: "
; INTERFACES - contracts for dependencies
class ILogger {
    Log(message) {
        throw Error(`"Must implement`")
    }
}

class IRepository {
    GetById(id) {
        throw Error(`"Must implement`")
    }
    Save(entity) {
        throw Error(`"Must implement`")
    }
}

; IMPLEMENTATIONS
class ConsoleLogger extends ILogger {
    _logs := []
    
    __New() {
        this._logs := []
    }
    
    Log(message) {
        entry := `"[`" . A_Now . `"] `" . message
        this._logs.Push(entry)
        return entry
    }
    
    GetLogs() {
        return this._logs
    }
}

class InMemoryUserRepo extends IRepository {
    _data := Map()
    _nextId := 1
    
    __New() {
        this._data := Map()
    }
    
    GetById(id) {
        return this._data.Has(id) ? this._data.Get(id) : `"`"
    }
    
    Save(entity) {
        if (!entity.HasOwnProp(`"Id`") || entity.Id = 0) {
            entity.Id := this._nextId++
        }
        this._data.Set(entity.Id, entity)
        return entity
    }
}

; SERVICE - receives dependencies via constructor
class UserService {
    _repo := `"`"
    _logger := `"`"
    
    ; CONSTRUCTOR INJECTION - dependencies passed in
    __New(repository, logger) {
        this._repo := repository
        this._logger := logger
    }
    
    CreateUser(name, email) {
        this._logger.Log(`"Creating user: `" . email)
        
        user := {Id: 0, Name: name, Email: email}
        savedUser := this._repo.Save(user)
        
        this._logger.Log(`"User created with ID: `" . savedUser.Id)
        return savedUser
    }
    
    GetUser(id) {
        this._logger.Log(`"Getting user: `" . id)
        return this._repo.GetById(id)
    }
}

; DI CONTAINER - manages object creation
class DIContainer {
    static _registry := Map()
    static _singletons := Map()
    
    static RegisterSingleton(name, factory) {
        DIContainer._registry.Set(name, {Factory: factory, IsSingleton: true})
    }
    
    static RegisterTransient(name, factory) {
        DIContainer._registry.Set(name, {Factory: factory, IsSingleton: false})
    }
    
    static Resolve(name) {
        if (!DIContainer._registry.Has(name)) {
            throw Error(`"Not registered: `" . name)
        }
        
        reg := DIContainer._registry.Get(name)
        
        if (reg.IsSingleton && DIContainer._singletons.Has(name)) {
            return DIContainer._singletons.Get(name)
        }
        
        instance := reg.Factory.Call()
        
        if (reg.IsSingleton) {
            DIContainer._singletons.Set(name, instance)
        }
        
        return instance
    }
    
    ; Configure all services
    static Configure() {
        DIContainer.RegisterSingleton(`"ILogger`", () => ConsoleLogger())
        DIContainer.RegisterSingleton(`"IRepository`", () => InMemoryUserRepo())
        
        ; UserService depends on ILogger and IRepository
        DIContainer.RegisterTransient(`"UserService`", () => UserService(
            DIContainer.Resolve(`"IRepository`"),
            DIContainer.Resolve(`"ILogger`")
        ))
    }
}

; USAGE
DIContainer.Configure()

userService := DIContainer.Resolve(`"UserService`")
user1 := userService.CreateUser(`"Alice`", `"alice@example.com`")
user2 := userService.CreateUser(`"Bob`", `"bob@example.com`")

found := userService.GetUser(1)

logger := DIContainer.Resolve(`"ILogger`")
output := `"Users created: `" . user1.Name . `", `" . user2.Name . `"`n`n`"
output .= `"Logs:`n`"
for entry in logger.GetLogs() {
    output .= entry . `"`n`"
}

MsgBox(output)
"
        }
        
        this.patternData["Architecture_Repository Pattern"] := {
            Name: "Repository Pattern",
            Definition: "Mediates between the domain and data mapping layers, acting like an in-memory collection of domain objects. Abstracts the data persistence mechanism.",
            WhyHow: "WHY USE IT:`n• To separate domain logic from data access logic`n• To provide a collection-like interface for accessing data`n• To make data access testable (can mock repository)`n• To centralize query logic and reduce duplication`n`nHOW IT WORKS:`n• Repository interface defines standard CRUD operations`n• Concrete repository implements interface for specific data store`n• Domain/service layer uses repository interface`n• Data store details hidden behind repository abstraction",
            Code: "
; ENTITY - domain object
class Product {
    Id := 0
    Name := `"`"
    Price := 0.0
    Stock := 0
    Category := `"`"
    
    __New(name, price, stock, category) {
        this.Name := name
        this.Price := price
        this.Stock := stock
        this.Category := category
    }
}

; REPOSITORY INTERFACE
class IProductRepository {
    GetById(id) {
        throw Error(`"Must implement`")
    }
    GetAll() {
        throw Error(`"Must implement`")
    }
    GetByCategory(category) {
        throw Error(`"Must implement`")
    }
    Add(product) {
        throw Error(`"Must implement`")
    }
    Update(product) {
        throw Error(`"Must implement`")
    }
    Delete(id) {
        throw Error(`"Must implement`")
    }
}

; CONCRETE REPOSITORY - in-memory implementation
class InMemoryProductRepository extends IProductRepository {
    _products := Map()
    _nextId := 1
    
    __New() {
        this._products := Map()
    }
    
    GetById(id) {
        return this._products.Has(id) ? this._products.Get(id) : `"`"
    }
    
    GetAll() {
        result := []
        for id, product in this._products {
            result.Push(product)
        }
        return result
    }
    
    GetByCategory(category) {
        result := []
        for id, product in this._products {
            if (product.Category = category) {
                result.Push(product)
            }
        }
        return result
    }
    
    Add(product) {
        product.Id := this._nextId++
        this._products.Set(product.Id, product)
        return product
    }
    
    Update(product) {
        if (!this._products.Has(product.Id)) {
            return false
        }
        this._products.Set(product.Id, product)
        return true
    }
    
    Delete(id) {
        if (!this._products.Has(id)) {
            return false
        }
        this._products.Delete(id)
        return true
    }
    
    ; Additional query methods
    GetLowStock(threshold) {
        result := []
        for id, product in this._products {
            if (product.Stock < threshold) {
                result.Push(product)
            }
        }
        return result
    }
}

; USAGE - service uses repository
class ProductService {
    _repo := `"`"
    
    __New(repository) {
        this._repo := repository
    }
    
    AddProduct(name, price, stock, category) {
        product := Product(name, price, stock, category)
        return this._repo.Add(product)
    }
    
    GetProductsByCategory(category) {
        return this._repo.GetByCategory(category)
    }
    
    GetLowStockAlert(threshold := 10) {
        return this._repo.GetLowStock(threshold)
    }
}

; Test it
repo := InMemoryProductRepository()
service := ProductService(repo)

service.AddProduct(`"Laptop`", 999.99, 15, `"Electronics`")
service.AddProduct(`"Mouse`", 29.99, 5, `"Electronics`")
service.AddProduct(`"Desk`", 199.99, 8, `"Furniture`")
service.AddProduct(`"Chair`", 149.99, 3, `"Furniture`")

electronics := service.GetProductsByCategory(`"Electronics`")
lowStock := service.GetLowStockAlert(10)

output := `"Electronics:`n`"
for p in electronics {
    output .= `"  `" . p.Name . `" - $`" . p.Price . `"`n`"
}

output .= `"`nLow Stock (< 10):`n`"
for p in lowStock {
    output .= `"  `" . p.Name . `" - Stock: `" . p.Stock . `"`n`"
}

MsgBox(output)
"
        }
        
        this.patternData["Architecture_Service Layer"] := {
            Name: "Service Layer",
            Definition: "Defines an application's boundary with a layer of services that establishes a set of available operations and coordinates the application's response to each operation.",
            WhyHow: "WHY USE IT:`n• To encapsulate business logic in one place`n• To provide a simplified interface for UI/controllers`n• To coordinate between multiple repositories/services`n• To handle transactions and cross-cutting concerns`n`nHOW IT WORKS:`n• Service classes contain business logic methods`n• Services use repositories for data access`n• Services enforce business rules and validation`n• Controllers/UI call services, not repositories directly",
            Code: "
; ENTITIES
class OrderItem {
    ProductId := 0
    Quantity := 0
    UnitPrice := 0.0
    
    __New(productId, quantity, unitPrice) {
        this.ProductId := productId
        this.Quantity := quantity
        this.UnitPrice := unitPrice
    }
    
    GetTotal() {
        return this.Quantity * this.UnitPrice
    }
}

class CustomerOrder {
    Id := 0
    CustomerId := 0
    Items := []
    Status := `"pending`"
    CreatedAt := `"`"
    
    __New(customerId) {
        this.CustomerId := customerId
        this.Items := []
        this.CreatedAt := A_Now
    }
    
    GetTotal() {
        total := 0
        for item in this.Items {
            total += item.GetTotal()
        }
        return total
    }
}

; OPERATION RESULT
class ServiceResult {
    Success := false
    Data := `"`"
    Error := `"`"
    
    static Ok(data) {
        r := ServiceResult()
        r.Success := true
        r.Data := data
        return r
    }
    
    static Fail(error) {
        r := ServiceResult()
        r.Success := false
        r.Error := error
        return r
    }
}

; SERVICE LAYER - coordinates business operations
class OrderService {
    _orderRepo := `"`"
    _productRepo := `"`"
    _logger := `"`"
    
    ; Dependencies injected
    __New(orderRepo, productRepo, logger) {
        this._orderRepo := orderRepo
        this._productRepo := productRepo
        this._logger := logger
    }
    
    ; Business operation: Create Order
    CreateOrder(customerId, items) {
        this._logger.Log(`"Creating order for customer `" . customerId)
        
        ; Validation
        if (items.Length = 0) {
            return ServiceResult.Fail(`"Order must have at least one item`")
        }
        
        ; Create order
        order := CustomerOrder(customerId)
        
        ; Validate and add items
        for itemData in items {
            product := this._productRepo.GetById(itemData.ProductId)
            if (product = `"`") {
                return ServiceResult.Fail(`"Product not found: `" . itemData.ProductId)
            }
            
            if (product.Stock < itemData.Quantity) {
                return ServiceResult.Fail(`"Insufficient stock for `" . product.Name)
            }
            
            ; Reduce stock
            product.Stock -= itemData.Quantity
            this._productRepo.Update(product)
            
            ; Add to order
            order.Items.Push(OrderItem(product.Id, itemData.Quantity, product.Price))
        }
        
        ; Save order
        savedOrder := this._orderRepo.Add(order)
        
        this._logger.Log(`"Order created: `" . savedOrder.Id . `" Total: $`" . savedOrder.GetTotal())
        
        return ServiceResult.Ok(savedOrder)
    }
    
    ; Business operation: Cancel Order
    CancelOrder(orderId) {
        order := this._orderRepo.GetById(orderId)
        
        if (order = `"`") {
            return ServiceResult.Fail(`"Order not found`")
        }
        
        if (order.Status = `"shipped`") {
            return ServiceResult.Fail(`"Cannot cancel shipped order`")
        }
        
        ; Restore stock
        for item in order.Items {
            product := this._productRepo.GetById(item.ProductId)
            if (product != `"`") {
                product.Stock += item.Quantity
                this._productRepo.Update(product)
            }
        }
        
        order.Status := `"cancelled`"
        this._orderRepo.Update(order)
        
        return ServiceResult.Ok(order)
    }
    
    ; Query operation
    GetOrderSummary(orderId) {
        order := this._orderRepo.GetById(orderId)
        
        if (order = `"`") {
            return ServiceResult.Fail(`"Order not found`")
        }
        
        summary := `"Order #`" . order.Id . `"`n`"
        summary .= `"Status: `" . order.Status . `"`n`"
        summary .= `"Items:`n`"
        
        for item in order.Items {
            summary .= `"  - Product `" . item.ProductId . `": `" . item.Quantity . `" x $`" . item.UnitPrice . `"`n`"
        }
        
        summary .= `"Total: $`" . Format(`"{:.2f}`", order.GetTotal())
        
        return ServiceResult.Ok(summary)
    }
}

; Simple mock repos for demo
class MockOrderRepo {
    _orders := Map()
    _nextId := 1
    
    __New() {
        this._orders := Map()
    }
    
    GetById(id) {
        return this._orders.Has(id) ? this._orders.Get(id) : `"`"
    }
    
    Add(order) {
        order.Id := this._nextId++
        this._orders.Set(order.Id, order)
        return order
    }
    
    Update(order) {
        this._orders.Set(order.Id, order)
        return true
    }
}

class MockProductRepo {
    _products := Map()
    
    __New() {
        this._products := Map()
        this._products.Set(1, {Id: 1, Name: `"Widget`", Price: 9.99, Stock: 100})
        this._products.Set(2, {Id: 2, Name: `"Gadget`", Price: 19.99, Stock: 50})
    }
    
    GetById(id) {
        return this._products.Has(id) ? this._products.Get(id) : `"`"
    }
    
    Update(product) {
        this._products.Set(product.Id, product)
    }
}

class MockLogger {
    _logs := []
    __New() {
        this._logs := []
    }
    Log(msg) {
        this._logs.Push(msg)
    }
}

; USAGE
orderRepo := MockOrderRepo()
productRepo := MockProductRepo()
logger := MockLogger()

orderService := OrderService(orderRepo, productRepo, logger)

; Create order
result := orderService.CreateOrder(101, [
    {ProductId: 1, Quantity: 3},
    {ProductId: 2, Quantity: 2}
])

output := `"`"
if (result.Success) {
    output := `"Order created!`n`n`"
    
    summaryResult := orderService.GetOrderSummary(result.Data.Id)
    output .= summaryResult.Data
} else {
    output := `"Error: `" . result.Error
}

MsgBox(output)
"
        }
        
        this.patternData["Architecture_Interfaces"] := {
            Name: "Interfaces",
            Definition: "Defines a contract that specifies what methods a class must implement, without dictating how they should be implemented. Enables polymorphism and loose coupling.",
            WhyHow: "WHY USE IT:`n• To define contracts between components`n• To enable dependency injection and mocking`n• To allow multiple implementations of same contract`n• To decouple code from specific implementations`n`nHOW IT WORKS:`n• Interface class declares methods that throw 'not implemented' errors`n• Implementing classes extend interface and override all methods`n• Code depends on interface, not concrete class`n• Different implementations can be swapped at runtime",
            Code: "
; INTERFACE DEFINITION
; In AHK, we simulate interfaces with classes that throw errors
class IEmailSender {
    Send(to, subject, body) {
        throw Error(`"IEmailSender.Send must be implemented`")
    }
    
    SendBulk(recipients, subject, body) {
        throw Error(`"IEmailSender.SendBulk must be implemented`")
    }
}

; IMPLEMENTATION 1: SMTP Email
class SmtpEmailSender extends IEmailSender {
    _server := `"`"
    _port := 0
    
    __New(server, port := 587) {
        this._server := server
        this._port := port
    }
    
    Send(to, subject, body) {
        ; Actual SMTP sending would happen here
        return `"SMTP: Sent to `" . to . `" via `" . this._server
    }
    
    SendBulk(recipients, subject, body) {
        results := []
        for recipient in recipients {
            results.Push(this.Send(recipient, subject, body))
        }
        return results
    }
}

; IMPLEMENTATION 2: Mock for testing
class MockEmailSender extends IEmailSender {
    _sentEmails := []
    
    __New() {
        this._sentEmails := []
    }
    
    Send(to, subject, body) {
        this._sentEmails.Push({To: to, Subject: subject, Body: body})
        return `"MOCK: Would send to `" . to
    }
    
    SendBulk(recipients, subject, body) {
        results := []
        for recipient in recipients {
            results.Push(this.Send(recipient, subject, body))
        }
        return results
    }
    
    ; Test helper methods
    GetSentCount() {
        return this._sentEmails.Length
    }
    
    GetLastEmail() {
        if (this._sentEmails.Length > 0) {
            return this._sentEmails[this._sentEmails.Length]
        }
        return `"`"
    }
}

; IMPLEMENTATION 3: Console logger (for debugging)
class ConsoleEmailSender extends IEmailSender {
    Send(to, subject, body) {
        return `"CONSOLE: Email to `" . to . `"`n  Subject: `" . subject . `"`n  Body: `" . body
    }
    
    SendBulk(recipients, subject, body) {
        results := []
        for recipient in recipients {
            results.Push(this.Send(recipient, subject, body))
        }
        return results
    }
}

; SERVICE THAT USES THE INTERFACE
class NotificationService {
    _emailSender := `"`"  ; IEmailSender - doesn't know which implementation
    
    __New(emailSender) {
        this._emailSender := emailSender
    }
    
    NotifyUser(userEmail, message) {
        return this._emailSender.Send(userEmail, `"Notification`", message)
    }
    
    NotifyAll(userEmails, message) {
        return this._emailSender.SendBulk(userEmails, `"Notification`", message)
    }
}

; USAGE - Switch implementations easily

; For development/debugging:
output := `"=== Development Mode ===`n`"
devSender := ConsoleEmailSender()
devService := NotificationService(devSender)
output .= devService.NotifyUser(`"dev@test.com`", `"Test message`") . `"`n`n`"

; For testing:
output .= `"=== Test Mode ===`n`"
mockSender := MockEmailSender()
testService := NotificationService(mockSender)
testService.NotifyUser(`"test1@test.com`", `"Hello`")
testService.NotifyUser(`"test2@test.com`", `"World`")
output .= `"Emails sent: `" . mockSender.GetSentCount() . `"`n`"
lastEmail := mockSender.GetLastEmail()
output .= `"Last email to: `" . lastEmail.To . `"`n`n`"

; For production:
output .= `"=== Production Mode ===`n`"
prodSender := SmtpEmailSender(`"smtp.company.com`", 587)
prodService := NotificationService(prodSender)
output .= prodService.NotifyUser(`"customer@example.com`", `"Important update`")

MsgBox(output)
"
        }
        
        this.patternData["Architecture_Value Objects"] := {
            Name: "Value Objects",
            Definition: "Small objects that represent simple entities whose equality is based on their value rather than their identity. They are immutable and have no conceptual identity.",
            WhyHow: "WHY USE IT:`n• To represent concepts like Money, Date, Address, Email`n• To ensure validity through construction`n• To make code more expressive and type-safe`n• To avoid 'primitive obsession' (using raw strings/numbers)`n`nHOW IT WORKS:`n• Value object encapsulates a value with validation`n• Equality based on value, not reference`n• Immutable - methods return new instances`n• Factory methods ensure valid construction",
            Code: "
; VALUE OBJECT: Email Address
class EmailAddress {
    _value := `"`"
    
    __New(email) {
        ; Validate on construction
        if (!InStr(email, `"@`")) {
            throw Error(`"Invalid email: must contain @`")
        }
        if (!InStr(email, `".`")) {
            throw Error(`"Invalid email: must contain .`")
        }
        this._value := StrLower(email)  ; Normalize
    }
    
    ; Factory method
    static Create(email) {
        try {
            return {Success: true, Value: EmailAddress(email)}
        } catch as err {
            return {Success: false, Error: err.Message}
        }
    }
    
    GetValue() {
        return this._value
    }
    
    GetDomain() {
        parts := StrSplit(this._value, `"@`")
        return parts.Length > 1 ? parts[2] : `"`"
    }
    
    Equals(other) {
        return this._value = other.GetValue()
    }
    
    ToString() {
        return this._value
    }
}

; VALUE OBJECT: Money
class Money {
    _amount := 0
    _currency := `"`"
    
    __New(amount, currency := `"USD`") {
        if (amount < 0) {
            throw Error(`"Money cannot be negative`")
        }
        this._amount := Round(amount, 2)
        this._currency := StrUpper(currency)
    }
    
    GetAmount() {
        return this._amount
    }
    
    GetCurrency() {
        return this._currency
    }
    
    ; Returns NEW Money object (immutable)
    Add(other) {
        if (this._currency != other.GetCurrency()) {
            throw Error(`"Cannot add different currencies`")
        }
        return Money(this._amount + other.GetAmount(), this._currency)
    }
    
    Subtract(other) {
        if (this._currency != other.GetCurrency()) {
            throw Error(`"Cannot subtract different currencies`")
        }
        newAmount := this._amount - other.GetAmount()
        if (newAmount < 0) {
            throw Error(`"Result would be negative`")
        }
        return Money(newAmount, this._currency)
    }
    
    Multiply(factor) {
        return Money(this._amount * factor, this._currency)
    }
    
    Equals(other) {
        return this._amount = other.GetAmount() && this._currency = other.GetCurrency()
    }
    
    ToString() {
        symbol := (this._currency = `"USD`") ? `"$`" : this._currency . `" `"
        return symbol . Format(`"{:.2f}`", this._amount)
    }
}

; VALUE OBJECT: DateRange
class DateRange {
    _startDate := `"`"
    _endDate := `"`"
    
    __New(startDate, endDate) {
        if (startDate > endDate) {
            throw Error(`"Start date must be before end date`")
        }
        this._startDate := startDate
        this._endDate := endDate
    }
    
    GetStart() {
        return this._startDate
    }
    
    GetEnd() {
        return this._endDate
    }
    
    Contains(date) {
        return date >= this._startDate && date <= this._endDate
    }
    
    Overlaps(other) {
        return this._startDate <= other.GetEnd() && this._endDate >= other.GetStart()
    }
    
    GetDurationDays() {
        ; Simplified - in real code use proper date math
        return 7  ; Placeholder
    }
    
    ToString() {
        return this._startDate . `" to `" . this._endDate
    }
}

; USAGE
output := `"=== Email Value Object ===`n`"
emailResult := EmailAddress.Create(`"User@Example.COM`")
if (emailResult.Success) {
    email := emailResult.Value
    output .= `"Email: `" . email.ToString() . `"`n`"
    output .= `"Domain: `" . email.GetDomain() . `"`n`n`"
}

badEmailResult := EmailAddress.Create(`"invalid-email`")
output .= `"Invalid email result: `" . badEmailResult.Error . `"`n`n`"

output .= `"=== Money Value Object ===`n`"
price := Money(29.99, `"USD`")
tax := Money(2.40, `"USD`")
total := price.Add(tax)

output .= `"Price: `" . price.ToString() . `"`n`"
output .= `"Tax: `" . tax.ToString() . `"`n`"
output .= `"Total: `" . total.ToString() . `"`n`n`"

quantity := 3
lineTotal := price.Multiply(quantity)
output .= `"Line total (x`" . quantity . `"): `" . lineTotal.ToString() . `"`n`n`"

output .= `"=== DateRange Value Object ===`n`"
vacation := DateRange(`"2024-07-01`", `"2024-07-15`")
output .= `"Vacation: `" . vacation.ToString() . `"`n`"
output .= `"Contains 2024-07-10: `" . (vacation.Contains(`"2024-07-10`") ? `"Yes`" : `"No`")

MsgBox(output)
"
        }
    }
    
    ; ══════════════════════════════════════════════════════════════════════════
    ; GET PATTERN DATA
    ; ══════════════════════════════════════════════════════════════════════════
    
    GetPatternData(category, patternName) {
        key := category . "_" . patternName
        if (this.patternData.Has(key)) {
            return this.patternData.Get(key)
        }
        return ""
    }
}

; ══════════════════════════════════════════════════════════════════════════════
; LAUNCH APPLICATION
; ══════════════════════════════════════════════════════════════════════════════

app := DesignPatternsReferenceApp()
