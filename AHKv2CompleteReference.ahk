;╔══════════════════════════════════════════════════════════════════════════════╗
; ║  AUTOHOTKEY V2 COMPLETE REFERENCE                                            ║
; ║  Design Patterns + Language Syntax - All in One                              ║
; ╚══════════════════════════════════════════════════════════════════════════════╝

#Requires AutoHotkey v2.0
#SingleInstance Force

; ══════════════════════════════════════════════════════════════════════════════
; MAIN APPLICATION
; ══════════════════════════════════════════════════════════════════════════════

class CompleteReferenceApp {
    mainGui := ""
    tabControl := ""
    currentList := ""
    currentName := ""
    currentDef := ""
    currentUsage := ""
    currentCode := ""
    data := Map()
    
    __New() {
        this.LoadAllData()
        this.CreateGui()
    }
    
    CreateGui() {
        this.mainGui := Gui("+Resize +MinSize1050x750")
        this.mainGui.Title := "AHK v2 Complete Reference - Patterns & Syntax"
        this.mainGui.BackColor := "0d1117"
        this.mainGui.SetFont("s10", "Segoe UI")
        
        ; Title
        title := this.mainGui.AddText("x20 y10 w1010 h30 Center c58a6ff", "AutoHotkey v2 Complete Reference")
        title.SetFont("s18 Bold", "Segoe UI")
        
        ; Main tabs
        this.tabControl := this.mainGui.AddTab3("x10 y50 w1030 h690 Background161b22", [
            "Creational Patterns",
            "Structural Patterns",
            "Behavioral Patterns",
            "Architecture",
            "───────────",
            "Variables",
            "Operators",
            "Control Flow",
            "Functions",
            "Classes"
        ])
        this.tabControl.SetFont("s9 cWhite", "Segoe UI")
        
        ; Build all tabs
        this.BuildTab(1, "Creational", ["Singleton", "Factory Method", "Abstract Factory", "Builder", "Prototype"])
        this.BuildTab(2, "Structural", ["Adapter", "Bridge", "Composite", "Decorator", "Facade", "Flyweight", "Proxy"])
        this.BuildTab(3, "Behavioral", ["Chain of Responsibility", "Command", "Iterator", "Mediator", "Memento", "Observer", "State", "Strategy", "Template Method", "Visitor"])
        this.BuildTab(4, "Architecture", ["Dependency Injection", "Repository Pattern", "Service Layer", "Interfaces", "Value Objects"])
        this.BuildSeparator(5)
        this.BuildTab(6, "Variables", ["Variable Basics", "Local Variables", "Global Variables", "Static Variables", "Strings", "Numbers", "Arrays", "Maps", "Objects"])
        this.BuildTab(7, "Operators", ["Assignment", "Arithmetic", "Comparison", "Logical", "Ternary", "String Concat", "Increment"])
        this.BuildTab(8, "ControlFlow", ["If Statement", "If-Else", "Switch", "Loop Count", "Loop Parse", "While Loop", "For Loop", "Break Continue", "Try-Catch"])
        this.BuildTab(9, "Functions", ["Function Basics", "Parameters", "Default Params", "Return Values", "Arrow Functions", "Closures", "Callbacks"])
        this.BuildTab(10, "Classes", ["Class Basics", "Constructor", "Properties", "Methods", "Static Members", "Inheritance", "Property GetSet"])
        
        this.tabControl.OnEvent("Change", (ctrl, *) => this.OnTabChange())
        this.mainGui.OnEvent("Close", (*) => ExitApp())
        
        this.mainGui.Show("w1050 h750")
        this.tabControl.Choose(1)
        this.OnTabChange()
    }
    
    BuildSeparator(tabNum) {
        this.tabControl.UseTab(tabNum)
        sep := this.mainGui.AddText("x400 y350 w300 h40 Center c444444", "─── Section Divider ───")
        sep.SetFont("s14 Italic", "Segoe UI")
    }
    
    BuildTab(tabNum, category, items) {
        this.tabControl.UseTab(tabNum)
        
        ; Left panel - list
        lbl := this.mainGui.AddText("x25 y95 w190 h20 cWhite", "Select Topic:")
        lbl.SetFont("s10 Bold", "Segoe UI")
        
        lb := this.mainGui.AddListBox("x25 y120 w190 h540 Background21262d cWhite v" . category . "_list", items)
        lb.SetFont("s10", "Consolas")
        lb.OnEvent("Change", (ctrl, *) => this.OnItemSelect(category))
        
        ; Right panel - details
        this.mainGui.AddText("x235 y95 w100 h20 cWhite Bold", "Name:")
        nm := this.mainGui.AddEdit("x235 y115 w780 h28 ReadOnly Background21262d c7ee787 v" . category . "_name", "")
        nm.SetFont("s11 Bold", "Consolas")
        
        this.mainGui.AddText("x235 y153 w100 h20 cWhite Bold", "Definition:")
        df := this.mainGui.AddEdit("x235 y173 w780 h55 ReadOnly Multi Background21262d cWhite v" . category . "_def", "")
        df.SetFont("s9", "Segoe UI")
        
        this.mainGui.AddText("x235 y238 w200 h20 cWhite Bold", "How It Works / When to Use:")
        us := this.mainGui.AddEdit("x235 y258 w780 h90 ReadOnly Multi VScroll Background21262d cWhite v" . category . "_usage", "")
        us.SetFont("s9", "Segoe UI")
        
        this.mainGui.AddText("x235 y358 w200 h20 cWhite Bold", "Code Example:")
        cd := this.mainGui.AddEdit("x235 y378 w780 h250 ReadOnly Multi VScroll HScroll Background0d1117 c7ee787 v" . category . "_code", "")
        cd.SetFont("s9", "Consolas")
        
        btn := this.mainGui.AddButton("x235 y638 w140 h32 v" . category . "_btn", "📋 Copy Code")
        btn.OnEvent("Click", (*) => this.CopyCode(category))
        
        ; Store control references
        this.data[category . "_listctrl"] := lb
    }
    
    OnTabChange() {
        tabIdx := this.tabControl.Value
        categories := ["Creational", "Structural", "Behavioral", "Architecture", "", "Variables", "Operators", "ControlFlow", "Functions", "Classes"]
        
        if (tabIdx >= 1 && tabIdx <= categories.Length) {
            cat := categories[tabIdx]
            if (cat != "" && this.data.Has(cat . "_listctrl")) {
                lb := this.data[cat . "_listctrl"]
                if (lb.Value = 0) {
                    lb.Choose(1)
                }
                this.OnItemSelect(cat)
            }
        }
    }
    
    OnItemSelect(category) {
        lb := this.data[category . "_listctrl"]
        if (lb.Value = 0)
            return
        
        selected := lb.Text
        key := category . "_" . selected
        
        if (this.data.Has(key)) {
            item := this.data[key]
            this.mainGui[category . "_name"].Value := item.Name
            this.mainGui[category . "_def"].Value := item.Def
            this.mainGui[category . "_usage"].Value := item.Usage
            this.mainGui[category . "_code"].Value := item.Code
        }
    }
    
    CopyCode(category) {
        code := this.mainGui[category . "_code"].Value
        if (code != "") {
            A_Clipboard := code
            ToolTip("Code copied!")
            SetTimer(() => ToolTip(), -1500)
        }
    }
    
    ; ══════════════════════════════════════════════════════════════════════════
    ; DATA LOADING
    ; ══════════════════════════════════════════════════════════════════════════
    
    LoadAllData() {
        this.LoadCreationalPatterns()
        this.LoadStructuralPatterns()
        this.LoadBehavioralPatterns()
        this.LoadArchitecturePatterns()
        this.LoadVariables()
        this.LoadOperators()
        this.LoadControlFlow()
        this.LoadFunctions()
        this.LoadClasses()
    }
    
    ; ──────────────────────────────────────────────────────────────────────────
    ; CREATIONAL PATTERNS
    ; ──────────────────────────────────────────────────────────────────────────
    
    LoadCreationalPatterns() {
        this.data["Creational_Singleton"] := {
            Name: "Singleton Pattern",
            Def: "Ensures a class has only ONE instance and provides a global point of access to it. The single instance is created lazily (only when first requested).",
            Usage: "
(
WHY USE IT:
• When exactly one object is needed (config manager, logger)
• For shared resources like connection pools
• To control access to a shared resource

HOW IT WORKS:
• Static property stores the single instance
• Static getter creates instance on first access
• All code receives the same instance
)",
            Code: "
(
class ConfigManager {
    ; Static variable stores the ONE instance
    static _instance := ""
    
    ; Static property - the access point
    static Instance {
        get {
            if (ConfigManager._instance = "") {
                ConfigManager._instance := ConfigManager()
            }
            return ConfigManager._instance
        }
    }
    
    ; Instance data
    _settings := Map()
    
    __New() {
        this._settings.Set("AppName", "My App")
        this._settings.Set("Version", "1.0")
    }
    
    Get(key) {
        return this._settings.Get(key, "")
    }
    
    Set(key, value) {
        this._settings.Set(key, value)
    }
}

; USAGE - Both point to SAME instance
config1 := ConfigManager.Instance
config2 := ConfigManager.Instance

config1.Set("Theme", "Dark")
MsgBox(config2.Get("Theme"))   ; "Dark" - same instance!
MsgBox(config1 = config2)      ; 1 (true)
)"
        }
        
        this.data["Creational_Factory Method"] := {
            Name: "Factory Method Pattern",
            Def: "Defines an interface for creating objects, but lets subclasses decide which class to instantiate. Defers instantiation to subclasses.",
            Usage: "
(
WHY USE IT:
• When a class cannot anticipate the type of objects it creates
• When you want subclasses to specify created objects
• To encapsulate object creation logic

HOW IT WORKS:
• Abstract Creator declares the factory method
• Concrete Creators override to return specific products
• Client works with Creator interface, not concrete classes
)",
            Code: "
(
; Product interface
class Document {
    content := ""
    Render() {
        ; Override in subclasses
    }
}

class PdfDocument extends Document {
    Render() {
        this.content := "PDF content rendered"
        return this.content
    }
}

class HtmlDocument extends Document {
    Render() {
        this.content := "<html>HTML content</html>"
        return this.content
    }
}

; Creator with factory method
class DocumentCreator {
    CreateDocument() {
        throw Error("Subclass must implement")
    }
    
    RenderDocument() {
        doc := this.CreateDocument()
        doc.Render()
        return doc
    }
}

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

; USAGE
creator := PdfCreator()
doc := creator.RenderDocument()
MsgBox(doc.content)
)"
        }
        
        this.data["Creational_Abstract Factory"] := {
            Name: "Abstract Factory Pattern",
            Def: "Provides an interface for creating families of related objects without specifying their concrete classes. Creates entire product families that work together.",
            Usage: "
(
WHY USE IT:
• When you need to create families of related objects
• Products from one family shouldn't mix with another
• For cross-platform UI components

HOW IT WORKS:
• Abstract Factory declares creation methods for each product
• Concrete Factories implement all methods for one family
• Switching families = changing one factory
)",
            Code: "
(
; Abstract products
class Button {
    Render() {
        return "Button"
    }
}

class TextBox {
    Render() {
        return "TextBox"
    }
}

; Windows family
class WinButton extends Button {
    Render() {
        return "[Windows Button]"
    }
}

class WinTextBox extends TextBox {
    Render() {
        return "|Windows TextBox|"
    }
}

; Mac family
class MacButton extends Button {
    Render() {
        return "(Mac Button)"
    }
}

class MacTextBox extends TextBox {
    Render() {
        return "[Mac TextBox]"
    }
}

; Factories
class WinFactory {
    CreateButton() {
        return WinButton()
    }
    CreateTextBox() {
        return WinTextBox()
    }
}

class MacFactory {
    CreateButton() {
        return MacButton()
    }
    CreateTextBox() {
        return MacTextBox()
    }
}

; USAGE - Switch family by changing factory
factory := WinFactory()
btn := factory.CreateButton()
txt := factory.CreateTextBox()
MsgBox(btn.Render() . "`n" . txt.Render())
)"
        }
        
        this.data["Creational_Builder"] := {
            Name: "Builder Pattern",
            Def: "Separates the construction of a complex object from its representation. Allows step-by-step construction with a fluent interface.",
            Usage: "
(
WHY USE IT:
• When objects have many optional parameters
• To avoid telescoping constructors
• When construction involves multiple steps

HOW IT WORKS:
• Builder has methods for each configurable part
• Each method returns 'this' for chaining
• Build() returns the finished object
)",
            Code: "
(
; Complex object to build
class Email {
    To := ""
    From := ""
    Subject := ""
    Body := ""
    Priority := "normal"
}

; Builder class
class EmailBuilder {
    _email := ""
    
    __New() {
        this._email := Email()
    }
    
    SetTo(recipient) {
        this._email.To := recipient
        return this
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
    
    SetHighPriority() {
        this._email.Priority := "high"
        return this
    }
    
    Build() {
        result := this._email
        this._email := Email()
        return result
    }
}

; USAGE - Fluent interface
email := EmailBuilder()
    .SetTo("user@example.com")
    .SetFrom("sender@example.com")
    .SetSubject("Hello!")
    .SetBody("Message content")
    .SetHighPriority()
    .Build()

MsgBox("To: " . email.To . "`nPriority: " . email.Priority)
)"
        }
        
        this.data["Creational_Prototype"] := {
            Name: "Prototype Pattern",
            Def: "Creates new objects by copying an existing object (prototype). Cloning instead of instantiating.",
            Usage: "
(
WHY USE IT:
• When object creation is expensive
• When you need copies with mostly same properties
• To avoid subclassing for every variation

HOW IT WORKS:
• Prototype has a Clone() method
• Clone creates new instance, copies properties
• Registry can store named prototypes
)",
            Code: "
(
class Shape {
    X := 0
    Y := 0
    Color := "Black"
    Type := "Rectangle"
    
    Clone() {
        copy := Shape()
        copy.X := this.X
        copy.Y := this.Y
        copy.Color := this.Color
        copy.Type := this.Type
        return copy
    }
    
    ToString() {
        return this.Type . " at (" . this.X . "," . this.Y . ") - " . this.Color
    }
}

; Registry for prototypes
class ShapeRegistry {
    static _prototypes := Map()
    
    static Register(name, shape) {
        ShapeRegistry._prototypes.Set(name, shape)
    }
    
    static GetClone(name) {
        if (ShapeRegistry._prototypes.Has(name)) {
            return ShapeRegistry._prototypes.Get(name).Clone()
        }
        return ""
    }
}

; USAGE
redSquare := Shape()
redSquare.Color := "Red"
redSquare.Type := "Square"
ShapeRegistry.Register("RedSquare", redSquare)

; Get clones
s1 := ShapeRegistry.GetClone("RedSquare")
s1.X := 100
s2 := ShapeRegistry.GetClone("RedSquare")
s2.X := 200

MsgBox(s1.ToString() . "`n" . s2.ToString())
)"
        }
    }
    
    ; ──────────────────────────────────────────────────────────────────────────
    ; STRUCTURAL PATTERNS
    ; ──────────────────────────────────────────────────────────────────────────
    
    LoadStructuralPatterns() {
        this.data["Structural_Adapter"] := {
            Name: "Adapter Pattern",
            Def: "Converts the interface of a class into another interface clients expect. Lets classes work together that couldn't otherwise due to incompatible interfaces.",
            Usage: "
(
WHY USE IT:
• To use existing class with incompatible interface
• To integrate legacy code with new systems
• To work with third-party libraries

HOW IT WORKS:
• Adapter wraps the incompatible class (adaptee)
• Adapter implements expected interface
• Adapter translates calls to adaptee's format
)",
            Code: "
(
; Target interface client expects
class ILogger {
    Log(message, level) {
        throw Error("Implement me")
    }
}

; Existing incompatible class
class LegacyLogger {
    WriteLog(typeCode, msg, timestamp) {
        return "[" . timestamp . "] " . typeCode . ": " . msg
    }
}

; Adapter bridges the gap
class LoggerAdapter extends ILogger {
    _legacy := ""
    
    __New(legacyLogger) {
        this._legacy := legacyLogger
    }
    
    Log(message, level) {
        typeCode := "INFO"
        if (level >= 3) {
            typeCode := "ERROR"
        }
        return this._legacy.WriteLog(typeCode, message, A_Now)
    }
}

; USAGE
legacy := LegacyLogger()
logger := LoggerAdapter(legacy)
MsgBox(logger.Log("User logged in", 1))
)"
        }
        
        this.data["Structural_Bridge"] := {
            Name: "Bridge Pattern",
            Def: "Decouples an abstraction from its implementation so both can vary independently. Separates 'what' from 'how'.",
            Usage: "
(
WHY USE IT:
• To avoid permanent binding between abstraction and implementation
• When both should be extensible via subclassing
• To prevent explosion of subclasses

HOW IT WORKS:
• Abstraction holds reference to Implementor
• Abstraction delegates work to Implementor
• Both can have independent hierarchies
)",
            Code: "
(
; Implementor - the 'how'
class MessageSender {
    Send(content) {
        throw Error("Implement me")
    }
}

class EmailSender extends MessageSender {
    Send(content) {
        return "EMAIL: " . content
    }
}

class SmsSender extends MessageSender {
    Send(content) {
        return "SMS: " . content
    }
}

; Abstraction - the 'what'
class Message {
    _sender := ""
    _content := ""
    
    __New(sender) {
        this._sender := sender
    }
    
    SetContent(text) {
        this._content := text
        return this
    }
    
    Send() {
        return this._sender.Send(this._content)
    }
}

class UrgentMessage extends Message {
    Send() {
        return this._sender.Send("URGENT: " . this._content)
    }
}

; USAGE - Mix and match
email := EmailSender()
sms := SmsSender()

msg1 := Message(email).SetContent("Hello")
msg2 := UrgentMessage(sms).SetContent("Alert!")

MsgBox(msg1.Send() . "`n" . msg2.Send())
)"
        }
        
        this.data["Structural_Composite"] := {
            Name: "Composite Pattern",
            Def: "Composes objects into tree structures to represent part-whole hierarchies. Lets clients treat individual objects and compositions uniformly.",
            Usage: "
(
WHY USE IT:
• For tree-like structures (files/folders, menus)
• To treat individual and group objects the same
• To simplify client code with complex structures

HOW IT WORKS:
• Component interface for both leaves and composites
• Leaf implements for individual objects
• Composite contains children and delegates
)",
            Code: "
(
; Leaf - individual object
class FileItem {
    _name := ""
    _size := 0
    
    __New(name, size) {
        this._name := name
        this._size := size
    }
    
    GetSize() {
        return this._size
    }
    
    Display(indent := 0) {
        spaces := ""
        Loop indent {
            spaces .= "  "
        }
        return spaces . "FILE: " . this._name
    }
}

; Composite - container
class FolderItem {
    _name := ""
    _children := []
    
    __New(name) {
        this._name := name
        this._children := []
    }
    
    Add(item) {
        this._children.Push(item)
        return this
    }
    
    GetSize() {
        total := 0
        for child in this._children {
            total += child.GetSize()
        }
        return total
    }
    
    Display(indent := 0) {
        spaces := ""
        Loop indent {
            spaces .= "  "
        }
        output := spaces . "FOLDER: " . this._name . "`n"
        for child in this._children {
            output .= child.Display(indent + 1) . "`n"
        }
        return output
    }
}

; USAGE
root := FolderItem("Documents")
    .Add(FileItem("readme.txt", 1024))
    .Add(FileItem("data.csv", 2048))

images := FolderItem("Images")
    .Add(FileItem("photo.jpg", 5000))

root.Add(images)
MsgBox(root.Display() . "`nTotal: " . root.GetSize() . " bytes")
)"
        }
        
        this.data["Structural_Decorator"] := {
            Name: "Decorator Pattern",
            Def: "Attaches additional responsibilities to an object dynamically. Provides flexible alternative to subclassing for extending functionality.",
            Usage: "
(
WHY USE IT:
• To add features without modifying original class
• When subclassing would cause explosion of classes
• To combine features in different ways at runtime

HOW IT WORKS:
• Decorator wraps a component
• Decorator forwards requests and adds behavior
• Multiple decorators can be stacked
)",
            Code: "
(
; Component
class TextComponent {
    _text := ""
    
    __New(text) {
        this._text := text
    }
    
    GetContent() {
        return this._text
    }
}

; Base decorator
class TextDecorator {
    _wrapped := ""
    
    __New(component) {
        this._wrapped := component
    }
    
    GetContent() {
        return this._wrapped.GetContent()
    }
}

; Concrete decorators
class BoldDecorator extends TextDecorator {
    GetContent() {
        return "**" . this._wrapped.GetContent() . "**"
    }
}

class ItalicDecorator extends TextDecorator {
    GetContent() {
        return "_" . this._wrapped.GetContent() . "_"
    }
}

class UpperDecorator extends TextDecorator {
    GetContent() {
        return StrUpper(this._wrapped.GetContent())
    }
}

; USAGE - Stack decorators
plain := TextComponent("Hello World")
bold := BoldDecorator(plain)
boldItalic := ItalicDecorator(bold)
shouting := UpperDecorator(boldItalic)

MsgBox("Plain: " . plain.GetContent()
    . "`nBold: " . bold.GetContent()
    . "`nBold+Italic: " . boldItalic.GetContent()
    . "`nAll: " . shouting.GetContent())
)"
        }
        
        this.data["Structural_Facade"] := {
            Name: "Facade Pattern",
            Def: "Provides a unified interface to a set of interfaces in a subsystem. Makes complex subsystems easier to use.",
            Usage: "
(
WHY USE IT:
• To simplify a complex subsystem
• To reduce coupling between clients and subsystem
• To provide single entry point to many APIs

HOW IT WORKS:
• Facade knows which classes handle which requests
• Facade delegates to appropriate subsystem objects
• Clients only interact with Facade
)",
            Code: "
(
; Complex subsystem classes
class VideoReader {
    Open(path) {
        return "Opened: " . path
    }
    Close() {
        return "Closed"
    }
}

class AudioExtractor {
    Extract(path) {
        return "Audio extracted"
    }
}

class VideoEncoder {
    SetCodec(codec) {
        return "Codec: " . codec
    }
    Encode() {
        return "Encoded"
    }
}

; FACADE - simple interface
class VideoConverter {
    _reader := ""
    _audio := ""
    _encoder := ""
    
    __New() {
        this._reader := VideoReader()
        this._audio := AudioExtractor()
        this._encoder := VideoEncoder()
    }
    
    Convert(input, output, format) {
        steps := []
        steps.Push(this._reader.Open(input))
        steps.Push(this._audio.Extract(input))
        codec := (format = "mp4") ? "H.264" : "VP9"
        steps.Push(this._encoder.SetCodec(codec))
        steps.Push(this._encoder.Encode())
        steps.Push(this._reader.Close())
        
        result := ""
        for step in steps {
            result .= step . "`n"
        }
        return result
    }
}

; USAGE - One simple call
converter := VideoConverter()
MsgBox(converter.Convert("movie.avi", "movie.mp4", "mp4"))
)"
        }
        
        this.data["Structural_Flyweight"] := {
            Name: "Flyweight Pattern",
            Def: "Uses sharing to support large numbers of fine-grained objects efficiently. Reduces memory by sharing common state.",
            Usage: "
(
WHY USE IT:
• When application uses many similar objects
• When storage costs are high due to quantity
• For text rendering, game particles, repeated elements

HOW IT WORKS:
• INTRINSIC state: Shared, stored in flyweight
• EXTRINSIC state: Varies, passed as parameters
• Factory ensures flyweights are shared
)",
            Code: "
(
; Flyweight - stores shared state
class CharGlyph {
    Char := ""
    Font := ""
    Size := 0
    
    __New(char, font, size) {
        this.Char := char
        this.Font := font
        this.Size := size
    }
    
    Render(x, y, color) {
        return "'" . this.Char . "' at (" . x . "," . y . ") " . color
    }
}

; Factory ensures sharing
class GlyphFactory {
    static _pool := Map()
    static _created := 0
    static _requests := 0
    
    static Get(char, font, size) {
        GlyphFactory._requests++
        key := char . "|" . font . "|" . size
        
        if (!GlyphFactory._pool.Has(key)) {
            GlyphFactory._pool.Set(key, CharGlyph(char, font, size))
            GlyphFactory._created++
        }
        return GlyphFactory._pool.Get(key)
    }
    
    static Stats() {
        return "Requests: " . GlyphFactory._requests
            . ", Created: " . GlyphFactory._created
    }
}

; USAGE - "HELLO" needs only 4 glyphs (L reused)
text := "HELLO"
Loop Parse, text {
    glyph := GlyphFactory.Get(A_LoopField, "Arial", 12)
}
MsgBox(GlyphFactory.Stats())
)"
        }
        
        this.data["Structural_Proxy"] := {
            Name: "Proxy Pattern",
            Def: "Provides a surrogate or placeholder for another object to control access to it.",
            Usage: "
(
WHY USE IT:
• Virtual Proxy: Lazy initialization of expensive objects
• Protection Proxy: Access control
• Caching Proxy: Cache results

HOW IT WORKS:
• Proxy implements same interface as real subject
• Proxy holds reference to real subject
• Proxy intercepts requests and adds control logic
)",
            Code: "
(
; Real subject - expensive
class Database {
    _connected := false
    
    __New() {
        ; Simulate expensive connection
        Sleep(100)
        this._connected := true
    }
    
    Query(sql) {
        return "Result: " . sql
    }
}

; Virtual Proxy - lazy loading
class LazyDbProxy {
    _db := ""
    _connStr := ""
    
    __New(connStr) {
        this._connStr := connStr
    }
    
    _EnsureConnected() {
        if (this._db = "") {
            this._db := Database()
        }
    }
    
    Query(sql) {
        this._EnsureConnected()
        return this._db.Query(sql)
    }
    
    IsConnected() {
        return (this._db != "")
    }
}

; USAGE
db := LazyDbProxy("server=localhost")
MsgBox("Connected? " . db.IsConnected())  ; false
result := db.Query("SELECT * FROM users") ; NOW connects
MsgBox("Connected? " . db.IsConnected())  ; true
)"
        }
    }
    
    ; ──────────────────────────────────────────────────────────────────────────
    ; BEHAVIORAL PATTERNS
    ; ──────────────────────────────────────────────────────────────────────────
    
    LoadBehavioralPatterns() {
        this.data["Behavioral_Chain of Responsibility"] := {
            Name: "Chain of Responsibility",
            Def: "Avoids coupling sender to receiver by giving multiple objects a chance to handle a request. Chains receivers and passes request along.",
            Usage: "
(
WHY USE IT:
• When multiple objects may handle a request
• When you want flexible handler assignment
• For event handling, logging, approval workflows

HOW IT WORKS:
• Handler defines interface with SetNext() and Handle()
• Each handler decides to process or pass along
• Client sends to first handler in chain
)",
            Code: "
(
class SupportHandler {
    _next := ""
    
    SetNext(handler) {
        this._next := handler
        return handler
    }
    
    Handle(ticket) {
        if (this._next != "") {
            return this._next.Handle(ticket)
        }
        return "No handler available"
    }
}

class TechSupport extends SupportHandler {
    Handle(ticket) {
        if (ticket.Type = "technical") {
            return "TECH: Resolved - " . ticket.Desc
        }
        return super.Handle(ticket)
    }
}

class BillingSupport extends SupportHandler {
    Handle(ticket) {
        if (ticket.Type = "billing") {
            return "BILLING: Resolved - " . ticket.Desc
        }
        return super.Handle(ticket)
    }
}

; USAGE
tech := TechSupport()
billing := BillingSupport()
tech.SetNext(billing)

t1 := {Type: "technical", Desc: "App crash"}
t2 := {Type: "billing", Desc: "Invoice"}
MsgBox(tech.Handle(t1) . "`n" . tech.Handle(t2))
)"
        }
        
        this.data["Behavioral_Command"] := {
            Name: "Command Pattern",
            Def: "Encapsulates a request as an object, enabling parameterization, queuing, logging, and undo operations.",
            Usage: "
(
WHY USE IT:
• To parameterize objects with operations
• To queue, schedule, or log operations
• To implement undo/redo functionality

HOW IT WORKS:
• Command interface declares Execute() and Undo()
• ConcreteCommand stores receiver and parameters
• Invoker manages command history
)",
            Code: "
(
; Receiver
class TextEditor {
    _text := ""
    
    GetText() {
        return this._text
    }
    Insert(text) {
        this._text .= text
    }
    Delete(count) {
        if (StrLen(this._text) >= count) {
            this._text := SubStr(this._text, 1, -count)
        }
    }
}

; Command
class InsertCmd {
    _editor := ""
    _text := ""
    
    __New(editor, text) {
        this._editor := editor
        this._text := text
    }
    
    Execute() {
        this._editor.Insert(this._text)
    }
    
    Undo() {
        this._editor.Delete(StrLen(this._text))
    }
}

; Invoker
class CommandManager {
    _history := []
    
    Execute(cmd) {
        cmd.Execute()
        this._history.Push(cmd)
    }
    
    Undo() {
        if (this._history.Length > 0) {
            cmd := this._history.Pop()
            cmd.Undo()
        }
    }
}

; USAGE
editor := TextEditor()
mgr := CommandManager()

mgr.Execute(InsertCmd(editor, "Hello "))
mgr.Execute(InsertCmd(editor, "World!"))
MsgBox(editor.GetText())      ; Hello World!

mgr.Undo()
MsgBox(editor.GetText())      ; Hello
)"
        }
        
        this.data["Behavioral_Iterator"] := {
            Name: "Iterator Pattern",
            Def: "Provides a way to access elements of a collection sequentially without exposing its underlying representation.",
            Usage: "
(
WHY USE IT:
• To traverse collections without exposing internals
• To support multiple traversal algorithms
• To provide uniform interface for different structures

HOW IT WORKS:
• Iterator interface: HasNext(), Next()
• Collection creates Iterator
• Multiple iterators can exist simultaneously
)",
            Code: "
(
class BookCollection {
    _books := []
    
    Add(title, author) {
        this._books.Push({Title: title, Author: author})
    }
    
    GetAt(index) {
        return this._books[index]
    }
    
    Count() {
        return this._books.Length
    }
    
    CreateIterator() {
        return BookIterator(this)
    }
}

class BookIterator {
    _collection := ""
    _pos := 1
    
    __New(collection) {
        this._collection := collection
    }
    
    HasNext() {
        return this._pos <= this._collection.Count()
    }
    
    Next() {
        book := this._collection.GetAt(this._pos)
        this._pos++
        return book
    }
    
    Reset() {
        this._pos := 1
    }
}

; USAGE
library := BookCollection()
library.Add("Design Patterns", "GoF")
library.Add("Clean Code", "Martin")

iter := library.CreateIterator()
output := ""
while (iter.HasNext()) {
    book := iter.Next()
    output .= book.Title . " by " . book.Author . "`n"
}
MsgBox(output)
)"
        }
        
        this.data["Behavioral_Mediator"] := {
            Name: "Mediator Pattern",
            Def: "Defines an object that encapsulates how objects interact. Promotes loose coupling by keeping objects from referring to each other directly.",
            Usage: "
(
WHY USE IT:
• When many objects communicate in complex ways
• To reduce chaotic dependencies
• For chat rooms, air traffic control, GUIs

HOW IT WORKS:
• Mediator interface defines communication method
• Colleagues know Mediator, not each other
• Mediator routes messages appropriately
)",
            Code: "
(
class ChatRoom {
    _users := []
    
    Register(user) {
        this._users.Push(user)
        user.SetRoom(this)
    }
    
    Send(message, sender) {
        for user in this._users {
            if (user != sender) {
                user.Receive(message, sender.Name)
            }
        }
    }
}

class ChatUser {
    Name := ""
    _room := ""
    _inbox := []
    
    __New(name) {
        this.Name := name
        this._inbox := []
    }
    
    SetRoom(room) {
        this._room := room
    }
    
    Send(message) {
        this._room.Send(message, this)
    }
    
    Receive(message, from) {
        this._inbox.Push(from . ": " . message)
    }
    
    GetInbox() {
        result := ""
        for msg in this._inbox {
            result .= msg . "`n"
        }
        return result
    }
}

; USAGE
room := ChatRoom()
alice := ChatUser("Alice")
bob := ChatUser("Bob")

room.Register(alice)
room.Register(bob)

alice.Send("Hello everyone!")
bob.Send("Hi Alice!")

MsgBox("Bob's inbox:`n" . bob.GetInbox())
)"
        }
        
        this.data["Behavioral_Memento"] := {
            Name: "Memento Pattern",
            Def: "Captures and externalizes an object's internal state so it can be restored later, without violating encapsulation.",
            Usage: "
(
WHY USE IT:
• To implement save/restore (undo, checkpoints)
• To snapshot state for later recovery
• For save games, transaction rollback

HOW IT WORKS:
• Originator creates memento with current state
• Memento stores state (opaque to others)
• Caretaker stores mementos, never examines them
)",
            Code: "
(
; Memento - stores state
class GameSave {
    _level := 0
    _score := 0
    _health := 0
    
    __New(level, score, health) {
        this._level := level
        this._score := score
        this._health := health
    }
    
    GetLevel() { return this._level }
    GetScore() { return this._score }
    GetHealth() { return this._health }
}

; Originator
class Game {
    Level := 1
    Score := 0
    Health := 100
    
    Play() {
        this.Level++
        this.Score += 100
        this.Health -= 10
    }
    
    Save() {
        return GameSave(this.Level, this.Score, this.Health)
    }
    
    Load(save) {
        this.Level := save.GetLevel()
        this.Score := save.GetScore()
        this.Health := save.GetHealth()
    }
    
    Status() {
        return "L:" . this.Level . " S:" . this.Score . " H:" . this.Health
    }
}

; USAGE
game := Game()
game.Play()
game.Play()
MsgBox("Before save: " . game.Status())

save := game.Save()  ; Save state

game.Play()
game.Play()
MsgBox("After more play: " . game.Status())

game.Load(save)      ; Restore
MsgBox("After load: " . game.Status())
)"
        }
        
        this.data["Behavioral_Observer"] := {
            Name: "Observer Pattern",
            Def: "Defines a one-to-many dependency so when one object changes state, all dependents are notified automatically.",
            Usage: "
(
WHY USE IT:
• When change in one object requires changing others
• When object should notify unknown number of objects
• For event handling, data binding, MVC

HOW IT WORKS:
• Subject maintains list of Observers
• Subject provides Attach/Detach/Notify
• Observers implement Update() method
)",
            Code: "
(
class Stock {
    _symbol := ""
    _price := 0.0
    _observers := []
    
    __New(symbol, price) {
        this._symbol := symbol
        this._price := price
        this._observers := []
    }
    
    Attach(observer) {
        this._observers.Push(observer)
    }
    
    SetPrice(newPrice) {
        this._price := newPrice
        this.Notify()
    }
    
    Notify() {
        for obs in this._observers {
            obs.Update(this._symbol, this._price)
        }
    }
    
    GetPrice() {
        return this._price
    }
}

class PriceDisplay {
    _name := ""
    _lastPrice := 0
    
    __New(name) {
        this._name := name
    }
    
    Update(symbol, price) {
        this._lastPrice := price
    }
    
    Show() {
        return this._name . ": $" . this._lastPrice
    }
}

; USAGE
apple := Stock("AAPL", 150)
display1 := PriceDisplay("Main")
display2 := PriceDisplay("Backup")

apple.Attach(display1)
apple.Attach(display2)

apple.SetPrice(155)
MsgBox(display1.Show() . "`n" . display2.Show())
)"
        }
        
        this.data["Behavioral_State"] := {
            Name: "State Pattern",
            Def: "Allows an object to alter its behavior when its internal state changes. The object appears to change its class.",
            Usage: "
(
WHY USE IT:
• When behavior depends on state
• When operations have large conditionals
• For state machines (orders, workflows, games)

HOW IT WORKS:
• Context holds reference to current State
• State interface defines state-specific behavior
• ConcreteStates handle transitions
)",
            Code: "
(
; States
class PendingState {
    Pay(order) {
        order.SetState(PaidState())
        return "Payment processed"
    }
    Ship(order) {
        return "Cannot ship: not paid"
    }
    GetName() {
        return "Pending"
    }
}

class PaidState {
    Pay(order) {
        return "Already paid"
    }
    Ship(order) {
        order.SetState(ShippedState())
        return "Order shipped"
    }
    GetName() {
        return "Paid"
    }
}

class ShippedState {
    Pay(order) {
        return "Already shipped"
    }
    Ship(order) {
        return "Already shipped"
    }
    GetName() {
        return "Shipped"
    }
}

; Context
class Order {
    _state := ""
    
    __New() {
        this._state := PendingState()
    }
    
    SetState(state) {
        this._state := state
    }
    
    Pay() {
        return this._state.Pay(this)
    }
    
    Ship() {
        return this._state.Ship(this)
    }
    
    Status() {
        return this._state.GetName()
    }
}

; USAGE
order := Order()
MsgBox("Status: " . order.Status())
MsgBox(order.Ship())       ; Cannot ship
MsgBox(order.Pay())        ; Payment processed
MsgBox("Status: " . order.Status())
MsgBox(order.Ship())       ; Order shipped
)"
        }
        
        this.data["Behavioral_Strategy"] := {
            Name: "Strategy Pattern",
            Def: "Defines a family of algorithms, encapsulates each one, and makes them interchangeable. Lets algorithm vary independently from clients.",
            Usage: "
(
WHY USE IT:
• When you need different variants of an algorithm
• To eliminate conditional statements for behavior
• When algorithm selection happens at runtime

HOW IT WORKS:
• Strategy interface declares algorithm method
• ConcreteStrategies implement differently
• Context uses Strategy without knowing details
)",
            Code: "
(
; Strategies
class CreditCardPay {
    Pay(amount) {
        return "Charged $" . amount . " to credit card"
    }
}

class PayPalPay {
    Pay(amount) {
        return "Paid $" . amount . " via PayPal"
    }
}

class CryptoPay {
    Pay(amount) {
        return "Sent " . (amount / 45000) . " BTC"
    }
}

; Context
class PaymentProcessor {
    _strategy := ""
    
    SetStrategy(strategy) {
        this._strategy := strategy
    }
    
    Checkout(amount) {
        if (this._strategy = "") {
            return "No payment method"
        }
        return this._strategy.Pay(amount)
    }
}

; USAGE - Switch at runtime
processor := PaymentProcessor()

processor.SetStrategy(CreditCardPay())
MsgBox(processor.Checkout(100))

processor.SetStrategy(PayPalPay())
MsgBox(processor.Checkout(50))

processor.SetStrategy(CryptoPay())
MsgBox(processor.Checkout(1000))
)"
        }
        
        this.data["Behavioral_Template Method"] := {
            Name: "Template Method Pattern",
            Def: "Defines the skeleton of an algorithm, deferring some steps to subclasses. Lets subclasses redefine steps without changing structure.",
            Usage: "
(
WHY USE IT:
• When algorithm has invariant and customizable parts
• To control which parts subclasses can override
• To avoid code duplication

HOW IT WORKS:
• Abstract class defines template method
• Template calls abstract/hook methods
• Subclasses override specific steps
)",
            Code: "
(
; Abstract class with template
class DataProcessor {
    ; TEMPLATE METHOD - the algorithm skeleton
    Process() {
        data := this.Load()
        if (!this.Validate(data)) {
            return "Validation failed"
        }
        result := this.Transform(data)
        this.Save(result)
        return "Done: " . result
    }
    
    ; Abstract - must override
    Load() {
        throw Error("Override Load()")
    }
    Transform(data) {
        throw Error("Override Transform()")
    }
    Save(data) {
        throw Error("Override Save()")
    }
    
    ; Hook - can override (has default)
    Validate(data) {
        return (data != "")
    }
}

class CsvProcessor extends DataProcessor {
    Load() {
        return "name,age`nAlice,30"
    }
    
    Transform(data) {
        return StrUpper(data)
    }
    
    Save(data) {
        ; Would save to file
    }
}

class JsonProcessor extends DataProcessor {
    Load() {
        return '{"name": "Test"}'
    }
    
    Transform(data) {
        return StrReplace(data, "Test", "Processed")
    }
    
    Save(data) {
        ; Would save to file
    }
}

; USAGE
csv := CsvProcessor()
MsgBox(csv.Process())

json := JsonProcessor()
MsgBox(json.Process())
)"
        }
        
        this.data["Behavioral_Visitor"] := {
            Name: "Visitor Pattern",
            Def: "Represents an operation on elements of an object structure. Lets you define new operations without changing the element classes.",
            Usage: "
(
WHY USE IT:
• To add operations without modifying element classes
• When many distinct operations are needed
• When element hierarchy is stable but operations change

HOW IT WORKS:
• Visitor declares Visit method for each element type
• Elements have Accept(visitor) calling visitor.Visit
• New operations = new Visitors
)",
            Code: "
(
; Elements
class Engineer {
    Name := ""
    Salary := 0
    Skills := []
    
    __New(name, salary, skills) {
        this.Name := name
        this.Salary := salary
        this.Skills := skills
    }
    
    Accept(visitor) {
        return visitor.VisitEngineer(this)
    }
}

class Manager {
    Name := ""
    Salary := 0
    TeamSize := 0
    
    __New(name, salary, teamSize) {
        this.Name := name
        this.Salary := salary
        this.TeamSize := teamSize
    }
    
    Accept(visitor) {
        return visitor.VisitManager(this)
    }
}

; Visitor - calculates total compensation
class SalaryVisitor {
    _total := 0
    
    VisitEngineer(eng) {
        bonus := eng.Skills.Length * 1000
        total := eng.Salary + bonus
        this._total += total
        return eng.Name . ": $" . total
    }
    
    VisitManager(mgr) {
        bonus := mgr.TeamSize * 500
        total := mgr.Salary + bonus
        this._total += total
        return mgr.Name . ": $" . total
    }
    
    GetTotal() {
        return this._total
    }
}

; USAGE
employees := [
    Engineer("Alice", 80000, ["Python", "Go"]),
    Manager("Bob", 90000, 5)
]

visitor := SalaryVisitor()
output := ""
for emp in employees {
    output .= emp.Accept(visitor) . "`n"
}
output .= "Total: $" . visitor.GetTotal()
MsgBox(output)
)"
        }
    }
    
    ; ──────────────────────────────────────────────────────────────────────────
    ; ARCHITECTURE
    ; ──────────────────────────────────────────────────────────────────────────
    
    LoadArchitecturePatterns() {
        this.data["Architecture_Dependency Injection"] := {
            Name: "Dependency Injection",
            Def: "A technique where an object receives its dependencies from external source rather than creating them itself. Implements Inversion of Control.",
            Usage: "
(
WHY USE IT:
• To decouple classes from dependencies
• To make code testable (inject mocks)
• To enable runtime configuration

HOW IT WORKS:
• Classes declare dependencies in constructors
• Container creates and wires objects
• Dependencies passed in, not created internally
)",
            Code: "
(
; Interface
class ILogger {
    Log(msg) {
        throw Error("Implement")
    }
}

; Implementation
class ConsoleLogger extends ILogger {
    _logs := []
    
    Log(msg) {
        this._logs.Push(msg)
    }
    
    GetLogs() {
        return this._logs
    }
}

; Service receives dependency
class UserService {
    _logger := ""
    
    __New(logger) {
        this._logger := logger
    }
    
    CreateUser(name) {
        this._logger.Log("Creating: " . name)
        return {Name: name, Id: Random(1, 1000)}
    }
}

; DI Container
class Container {
    static _services := Map()
    
    static Register(name, factory) {
        Container._services.Set(name, factory)
    }
    
    static Resolve(name) {
        return Container._services.Get(name).Call()
    }
}

; Configure
Container.Register("Logger", () => ConsoleLogger())
Container.Register("UserService", () => 
    UserService(Container.Resolve("Logger")))

; USAGE
svc := Container.Resolve("UserService")
user := svc.CreateUser("Alice")
MsgBox("Created user: " . user.Name)
)"
        }
        
        this.data["Architecture_Repository Pattern"] := {
            Name: "Repository Pattern",
            Def: "Mediates between domain and data mapping layers. Acts like in-memory collection of domain objects while abstracting persistence.",
            Usage: "
(
WHY USE IT:
• To separate domain from data access logic
• To provide collection-like interface for data
• To centralize query logic

HOW IT WORKS:
• Repository defines CRUD operations
• Concrete repository handles specific storage
• Domain uses repository interface
)",
            Code: "
(
; Entity
class Product {
    Id := 0
    Name := ""
    Price := 0
    
    __New(name, price) {
        this.Name := name
        this.Price := price
    }
}

; Repository
class ProductRepo {
    _data := Map()
    _nextId := 1
    
    GetById(id) {
        return this._data.Has(id) ? this._data.Get(id) : ""
    }
    
    GetAll() {
        result := []
        for id, prod in this._data {
            result.Push(prod)
        }
        return result
    }
    
    Add(product) {
        product.Id := this._nextId++
        this._data.Set(product.Id, product)
        return product
    }
    
    Delete(id) {
        this._data.Delete(id)
    }
}

; USAGE
repo := ProductRepo()
repo.Add(Product("Widget", 9.99))
repo.Add(Product("Gadget", 19.99))

products := repo.GetAll()
output := ""
for p in products {
    output .= p.Id . ": " . p.Name . " - $" . p.Price . "`n"
}
MsgBox(output)
)"
        }
        
        this.data["Architecture_Service Layer"] := {
            Name: "Service Layer",
            Def: "Defines application's boundary with services that establish available operations and coordinate responses.",
            Usage: "
(
WHY USE IT:
• To encapsulate business logic
• To provide simplified interface for UI
• To coordinate between repositories

HOW IT WORKS:
• Services contain business logic
• Services use repositories for data
• Controllers call services
)",
            Code: "
(
; Result type
class Result {
    Success := false
    Data := ""
    Error := ""
    
    static Ok(data) {
        r := Result()
        r.Success := true
        r.Data := data
        return r
    }
    
    static Fail(error) {
        r := Result()
        r.Error := error
        return r
    }
}

; Service
class OrderService {
    _repo := ""
    
    __New(orderRepo) {
        this._repo := orderRepo
    }
    
    CreateOrder(customerId, items) {
        if (items.Length = 0) {
            return Result.Fail("No items")
        }
        
        order := {
            CustomerId: customerId,
            Items: items,
            Total: 0
        }
        
        for item in items {
            order.Total += item.Price
        }
        
        saved := this._repo.Add(order)
        return Result.Ok(saved)
    }
}

; Simple repo for demo
class OrderRepo {
    _orders := []
    Add(order) {
        this._orders.Push(order)
        return order
    }
}

; USAGE
svc := OrderService(OrderRepo())
result := svc.CreateOrder(1, [{Name: "Item", Price: 10}])

if (result.Success) {
    MsgBox("Order total: $" . result.Data.Total)
} else {
    MsgBox("Error: " . result.Error)
}
)"
        }
        
        this.data["Architecture_Interfaces"] := {
            Name: "Interfaces (Contracts)",
            Def: "Defines a contract specifying what methods a class must implement, without dictating implementation. Enables polymorphism.",
            Usage: "
(
WHY USE IT:
• To define contracts between components
• To enable dependency injection and mocking
• To allow multiple implementations

HOW IT WORKS:
• Interface declares methods that throw errors
• Implementing classes extend and override
• Code depends on interface, not concrete class
)",
            Code: "
(
; Interface
class IEmailSender {
    Send(to, subject, body) {
        throw Error("Implement Send()")
    }
}

; Implementation 1: Real
class SmtpSender extends IEmailSender {
    Send(to, subject, body) {
        return "SMTP: Sent to " . to
    }
}

; Implementation 2: Mock for testing
class MockSender extends IEmailSender {
    _sent := []
    
    Send(to, subject, body) {
        this._sent.Push({To: to, Subject: subject})
        return "MOCK: Would send to " . to
    }
    
    GetSentCount() {
        return this._sent.Length
    }
}

; Service uses interface
class NotificationService {
    _sender := ""
    
    __New(emailSender) {
        this._sender := emailSender
    }
    
    Notify(email, message) {
        return this._sender.Send(email, "Notice", message)
    }
}

; USAGE - swap implementations
mock := MockSender()
svc := NotificationService(mock)
svc.Notify("test@test.com", "Hello")
svc.Notify("other@test.com", "World")
MsgBox("Emails sent: " . mock.GetSentCount())
)"
        }
        
        this.data["Architecture_Value Objects"] := {
            Name: "Value Objects",
            Def: "Small objects whose equality is based on value, not identity. They are immutable and represent concepts like Money, Email, DateRange.",
            Usage: "
(
WHY USE IT:
• To represent concepts like Money, Email, Address
• To ensure validity through construction
• To avoid primitive obsession

HOW IT WORKS:
• Encapsulates value with validation
• Equality based on value
• Immutable - methods return new instances
)",
            Code: "
(
class EmailAddress {
    _value := ""
    
    __New(email) {
        if (!InStr(email, "@")) {
            throw Error("Invalid email")
        }
        this._value := StrLower(email)
    }
    
    GetValue() {
        return this._value
    }
    
    GetDomain() {
        parts := StrSplit(this._value, "@")
        return parts[2]
    }
    
    Equals(other) {
        return this._value = other.GetValue()
    }
}

class Money {
    _amount := 0
    _currency := ""
    
    __New(amount, currency := "USD") {
        if (amount < 0) {
            throw Error("Negative amount")
        }
        this._amount := Round(amount, 2)
        this._currency := currency
    }
    
    Add(other) {
        if (this._currency != other._currency) {
            throw Error("Currency mismatch")
        }
        return Money(this._amount + other._amount, this._currency)
    }
    
    ToString() {
        return "$" . this._amount
    }
}

; USAGE
email := EmailAddress("User@Example.COM")
MsgBox("Email: " . email.GetValue())
MsgBox("Domain: " . email.GetDomain())

price := Money(19.99)
tax := Money(1.60)
total := price.Add(tax)
MsgBox("Total: " . total.ToString())
)"
        }
    }
    
    ; ──────────────────────────────────────────────────────────────────────────
    ; VARIABLES
    ; ──────────────────────────────────────────────────────────────────────────
    
    LoadVariables() {
        this.data["Variables_Variable Basics"] := {
            Name: "Variable Declaration",
            Def: "Variables in AHK v2 are created by assigning a value with :=. No declaration keyword needed. Names are case-insensitive.",
            Usage: "
(
• Use := for expression assignment
• Names can contain letters, numbers, underscore
• Names cannot start with a number
• myVar = MYVAR = MyVar (case-insensitive)
)",
            Code: "
(
; Creating variables
name := "Alice"          ; String
age := 30                ; Integer
price := 19.99           ; Float
active := true           ; Boolean

; Multiple assignment
x := y := z := 0         ; All three = 0

; Variable naming
userName := "Bob"        ; camelCase
user_name := "Bob"       ; snake_case
_private := "hidden"     ; underscore prefix

MsgBox("Name: " . name . ", Age: " . age)
)"
        }
        
        this.data["Variables_Local Variables"] := {
            Name: "local myVar := value",
            Def: "Local variables exist only within the function where declared. Destroyed when function ends. Default behavior in functions.",
            Usage: "
(
• Declared inside functions with 'local'
• Only accessible within declaring function
• Destroyed when function returns
• Default behavior (can omit 'local')
)",
            Code: "
(
MyFunction() {
    ; Explicitly local
    local message := "Hello"
    local counter := 0
    
    ; Also local (default in functions)
    result := message . " - " . counter
    
    return result
}

; Local doesn't affect outside
message := "Global"
MsgBox(MyFunction())   ; Function's local
MsgBox(message)        ; Still "Global"
)"
        }
        
        this.data["Variables_Global Variables"] := {
            Name: "global myVar := value",
            Def: "Global variables are accessible from anywhere. Persist for script lifetime. Use 'global' keyword inside functions.",
            Usage: "
(
• Declared outside functions (auto global)
• Use 'global' in functions to access
• Persist for entire script lifetime
• Use sparingly to avoid conflicts
)",
            Code: "
(
; Global (outside functions)
AppName := "My App"
Counter := 0

IncrementCounter() {
    global Counter   ; Access global
    Counter++
}

SetAppName(name) {
    global AppName := name   ; Access and modify
}

; Usage
IncrementCounter()
IncrementCounter()
MsgBox("Counter: " . Counter)   ; 2
)"
        }
        
        this.data["Variables_Static Variables"] := {
            Name: "static myVar := value",
            Def: "Static variables retain value between function calls. Initialized only once on first call. Persist until script ends.",
            Usage: "
(
• Declared with 'static' in functions
• Initialized only on first call
• Retain value between calls
• Great for counters, caching
)",
            Code: "
(
CountCalls() {
    static callCount := 0   ; Init once
    callCount++
    return callCount
}

MsgBox(CountCalls())   ; 1
MsgBox(CountCalls())   ; 2
MsgBox(CountCalls())   ; 3

GenerateId() {
    static lastId := 0
    lastId++
    return "ID-" . Format("{:04}", lastId)
}

MsgBox(GenerateId())   ; ID-0001
MsgBox(GenerateId())   ; ID-0002
)"
        }
        
        this.data["Variables_Strings"] := {
            Name: "Strings",
            Def: "Strings are text in double or single quotes. Support escape sequences and concatenation with dot operator.",
            Usage: "
(
• Double quotes: "text"
• Single quotes: 'text'
• Backtick escapes: `n newline, `t tab
• Concatenate with dot: "a" . "b"
)",
            Code: "
(
; Basic strings
simple := "Hello World"
withQuotes := "She said ``"Hi``""

; Escape sequences
newLine := "Line 1`nLine 2"
tabbed := "Col1`tCol2"

; Concatenation
first := "John"
last := "Doe"
full := first . " " . last

; String functions
text := "Hello"
MsgBox(StrLen(text))           ; 5
MsgBox(SubStr(text, 1, 3))     ; Hel
MsgBox(StrUpper(text))         ; HELLO
MsgBox(StrReplace(text, "l", "L"))  ; HeLLo
)"
        }
        
        this.data["Variables_Numbers"] := {
            Name: "Numbers",
            Def: "Numbers can be integers or floats. Supports decimal, hex (0x), and scientific notation.",
            Usage: "
(
• Integer: 42, -100
• Float: 3.14, -0.5
• Hex: 0xFF, 0x1A2B
• Scientific: 1e10, 2.5e-3
)",
            Code: "
(
; Number types
intVal := 42
floatVal := 3.14159
hexVal := 0xFF          ; 255

; Math operations
sum := 10 + 5           ; 15
diff := 10 - 5          ; 5
product := 10 * 5       ; 50
quotient := 10 / 3      ; 3.333...
intDiv := 10 // 3       ; 3 (integer division)
remainder := Mod(10, 3) ; 1
power := 2 ** 10        ; 1024

; Rounding
MsgBox(Round(3.7))      ; 4
MsgBox(Floor(3.9))      ; 3
MsgBox(Ceil(3.1))       ; 4
)"
        }
        
        this.data["Variables_Arrays"] := {
            Name: "Arrays",
            Def: "Arrays are ordered collections. 1-indexed (first element at index 1). Can hold mixed types and grow dynamically.",
            Usage: "
(
• Create: [item1, item2, ...]
• Access: arr[1] (first element)
• Add: arr.Push(value)
• Length: arr.Length
• Loop: for value in arr
)",
            Code: "
(
; Creating arrays
empty := []
numbers := [1, 2, 3, 4, 5]
mixed := ["text", 42, true]

; Accessing (1-indexed!)
first := numbers[1]       ; 1
last := numbers[-1]       ; 5

; Modifying
numbers[1] := 10
numbers.Push(6)           ; Add to end
numbers.RemoveAt(1)       ; Remove first

; Looping
for value in numbers {
    MsgBox(value)
}

; With index
for index, value in numbers {
    MsgBox(index . ": " . value)
}

; From string
parts := StrSplit("a,b,c", ",")
)"
        }
        
        this.data["Variables_Maps"] := {
            Name: "Maps (Dictionaries)",
            Def: "Maps are key-value collections. Keys can be any type. Provide fast lookup.",
            Usage: "
(
• Create: Map("key", value)
• Access: map[key] or map.Get(key)
• Add: map.Set(key, value) or map[key] := value
• Check: map.Has(key)
• Count: map.Count
)",
            Code: "
(
; Creating Maps
empty := Map()
ages := Map("Alice", 30, "Bob", 25)

; Adding/updating
ages.Set("Charlie", 35)
ages["Alice"] := 31

; Getting values
age := ages["Bob"]
safe := ages.Get("Dave", 0)  ; 0 if not found

; Check existence
if (ages.Has("Alice")) {
    MsgBox("Has Alice")
}

; Loop
for name, age in ages {
    MsgBox(name . " is " . age)
}

; Delete
ages.Delete("Bob")
MsgBox("Count: " . ages.Count)
)"
        }
        
        this.data["Variables_Objects"] := {
            Name: "Objects",
            Def: "Objects are property collections with dot notation access. Property names must be valid identifiers.",
            Usage: "
(
• Create: {prop: value, ...}
• Access: obj.property
• Add: obj.newProp := value
• Check: obj.HasOwnProp("name")
• Clone: obj.Clone()
)",
            Code: "
(
; Creating objects
person := {
    name: "Alice",
    age: 30,
    city: "NYC"
}

; Access
MsgBox(person.name)
MsgBox(person["age"])

; Modify
person.age := 31
person.email := "alice@test.com"

; Nested objects
company := {
    name: "TechCorp",
    address: {
        street: "123 Main",
        city: "NYC"
    }
}
MsgBox(company.address.city)

; Check property
if (person.HasOwnProp("email")) {
    MsgBox(person.email)
}

; Clone
copy := person.Clone()
copy.name := "Bob"   ; Doesn't affect original
)"
        }
    }
    
    ; ──────────────────────────────────────────────────────────────────────────
    ; OPERATORS
    ; ──────────────────────────────────────────────────────────────────────────
    
    LoadOperators() {
        this.data["Operators_Assignment"] := {
            Name: "Assignment Operators",
            Def: "The := operator evaluates the right side and assigns to the left. Multiple assignment works right to left.",
            Usage: "
(
• := expression assignment
• a := b := c := 0 (chain)
• obj.prop := value
• arr[1] := value
)",
            Code: "
(
; Basic assignment
name := "Alice"
age := 30

; Expression evaluated first
sum := 10 + 20         ; 30

; Multiple assignment
a := b := c := 0       ; All = 0
x := y := 10 + 5       ; Both = 15

; Object/array assignment
person := {}
person.name := "Bob"

arr := [1, 2, 3]
arr[1] := 100

; Map assignment
scores := Map()
scores["Alice"] := 95
)"
        }
        
        this.data["Operators_Arithmetic"] := {
            Name: "Arithmetic Operators",
            Def: "Math operations: +, -, *, /, //, Mod, **",
            Usage: "
(
• + Addition
• - Subtraction  
• * Multiplication
• / Division (float result)
• // Integer division
• Mod - Remainder
• ** Exponentiation
)",
            Code: "
(
a := 10
b := 3

sum := a + b           ; 13
diff := a - b          ; 7
product := a * b       ; 30
quotient := a / b      ; 3.333...
intDiv := a // b       ; 3
remainder := Mod(a, b) ; 1
power := 2 ** 10       ; 1024

; Order of operations
result := 2 + 3 * 4    ; 14 (not 20)
result := (2 + 3) * 4  ; 20
)"
        }
        
        this.data["Operators_Comparison"] := {
            Name: "Comparison Operators",
            Def: "Compare values, return true (1) or false (0). = is case-insensitive, == is case-sensitive for strings.",
            Usage: "
(
• = Equal (case-insensitive strings)
• == Equal (case-sensitive)
• != or <> Not equal
• < > <= >= Relational
)",
            Code: "
(
a := 5
b := 10

MsgBox(a = 5)          ; 1 (true)
MsgBox(a != b)         ; 1 (true)
MsgBox(a < b)          ; 1 (true)
MsgBox(a >= 5)         ; 1 (true)

; Case sensitivity
s1 := "Hello"
s2 := "hello"
MsgBox(s1 = s2)        ; 1 (case-insensitive)
MsgBox(s1 == s2)       ; 0 (case-sensitive)
)"
        }
        
        this.data["Operators_Logical"] := {
            Name: "Logical Operators",
            Def: "Combine boolean expressions. Short-circuit evaluation - right side skipped if result already determined.",
            Usage: "
(
• && AND - both true
• || OR - either true
• ! NOT - invert
• Short-circuit: stops early
)",
            Code: "
(
a := true
b := false

MsgBox(a && a)         ; 1 (true AND true)
MsgBox(a && b)         ; 0 (true AND false)
MsgBox(a || b)         ; 1 (true OR false)
MsgBox(!a)             ; 0 (NOT true)

; Practical use
x := 5
if (x > 0 && x < 10) {
    MsgBox("x is 1-9")
}

; Default value with ||
name := ""
display := name || "Guest"
)"
        }
        
        this.data["Operators_Ternary"] := {
            Name: "Ternary Operator (?:)",
            Def: "Compact if-else expression. Returns one of two values based on condition.",
            Usage: "
(
• condition ? trueValue : falseValue
• Returns trueValue if condition truthy
• Returns falseValue if condition falsy
• Can be nested
)",
            Code: "
(
age := 20
status := (age >= 18) ? "Adult" : "Minor"
MsgBox(status)         ; "Adult"

; Nested (use sparingly)
score := 85
grade := (score >= 90) ? "A"
       : (score >= 80) ? "B"
       : (score >= 70) ? "C"
       : "F"
MsgBox(grade)          ; "B"

; In expressions
value := -5
MsgBox("Value is " . (value >= 0 ? "positive" : "negative"))
)"
        }
        
        this.data["Operators_String Concat"] := {
            Name: "String Concatenation (.)",
            Def: "The dot operator joins strings. Auto-converts numbers. Use spaces around dot.",
            Usage: "
(
• "a" . "b" = "ab"
• Numbers auto-convert
• Spaces around dot for clarity
• Chain multiple: a . b . c
)",
            Code: "
(
first := "Hello"
second := "World"
combined := first . " " . second

; Numbers convert automatically
age := 30
msg := "Age: " . age

; Building in loop
result := ""
Loop 3 {
    result .= "Item " . A_Index . "`n"
}
MsgBox(result)

; .= compound assignment
text := "Hello"
text .= " World"       ; "Hello World"
)"
        }
        
        this.data["Operators_Increment"] := {
            Name: "Increment/Decrement (++, --)",
            Def: "++ adds 1, -- subtracts 1. Prefix (++n) returns new value; postfix (n++) returns old value then changes.",
            Usage: "
(
• ++n - increment, return new
• n++ - return old, then increment
• --n - decrement, return new
• n-- - return old, then decrement
)",
            Code: "
(
; Basic
count := 5
count++                ; 6
count--                ; 5

; Prefix vs Postfix
n := 5
result := ++n          ; n=6, result=6

n := 5  
result := n++          ; result=5, n=6

; In loops
i := 0
while (i < 5) {
    MsgBox(++i)        ; 1, 2, 3, 4, 5
}
)"
        }
    }
    
    ; ──────────────────────────────────────────────────────────────────────────
    ; CONTROL FLOW
    ; ──────────────────────────────────────────────────────────────────────────
    
    LoadControlFlow() {
        this.data["ControlFlow_If Statement"] := {
            Name: "If Statement",
            Def: "Executes block if condition is true (non-zero, non-empty). Braces required for multiple statements.",
            Usage: "
(
• if (condition) { ... }
• Truthy: non-zero, non-empty
• Falsy: 0, "", false
• Combine with && || !
)",
            Code: "
(
age := 25
if (age >= 18) {
    MsgBox("Adult")
}

; Multiple conditions
score := 85
if (score >= 70 && score < 90) {
    MsgBox("Grade B")
}

; Checking strings
name := "Alice"
if (name != "") {
    MsgBox("Hello, " . name)
}

; Negation
isAdmin := false
if (!isAdmin) {
    MsgBox("Not admin")
}
)"
        }
        
        this.data["ControlFlow_If-Else"] := {
            Name: "If-Else Statement",
            Def: "Provides alternative when condition is false. Exactly one block executes. Chain with else if.",
            Usage: "
(
• if (cond) { } else { }
• else if for chaining
• Only one block runs
• Can nest (use else if instead)
)",
            Code: "
(
age := 15
if (age >= 18) {
    MsgBox("Adult")
} else {
    MsgBox("Minor")
}

; Else if chain
score := 85
if (score >= 90) {
    grade := "A"
} else if (score >= 80) {
    grade := "B"
} else if (score >= 70) {
    grade := "C"
} else {
    grade := "F"
}
MsgBox("Grade: " . grade)
)"
        }
        
        this.data["ControlFlow_Switch"] := {
            Name: "Switch Statement",
            Def: "Compares value against multiple cases. No fall-through. Default handles unmatched.",
            Usage: "
(
• switch value { case x: ... }
• No fall-through (unlike C)
• Multiple values: case 1, 2:
• default for unmatched
)",
            Code: "
(
day := 3
switch day {
    case 1:
        name := "Monday"
    case 2:
        name := "Tuesday"
    case 3:
        name := "Wednesday"
    case 6, 7:
        name := "Weekend"
    default:
        name := "Other"
}
MsgBox(name)

; With strings
cmd := "save"
switch cmd {
    case "new":
        MsgBox("New file")
    case "save":
        MsgBox("Saving...")
    default:
        MsgBox("Unknown")
}
)"
        }
        
        this.data["ControlFlow_Loop Count"] := {
            Name: "Loop (Count)",
            Def: "Repeats block specified number of times. A_Index is current iteration (1-based).",
            Usage: "
(
• Loop n { ... }
• A_Index = current (1 to n)
• Break to exit early
• Continue to skip iteration
)",
            Code: "
(
; Basic loop
Loop 5 {
    MsgBox("Iteration " . A_Index)
}

; Building string
result := ""
Loop 3 {
    result .= "Line " . A_Index . "`n"
}
MsgBox(result)

; With break
Loop 100 {
    if (A_Index = 5) {
        break
    }
    MsgBox(A_Index)    ; 1, 2, 3, 4
}

; Skip evens with continue
Loop 10 {
    if (Mod(A_Index, 2) = 0) {
        continue
    }
    MsgBox(A_Index)    ; 1, 3, 5, 7, 9
}
)"
        }
        
        this.data["ControlFlow_Loop Parse"] := {
            Name: "Loop Parse",
            Def: "Iterates through substrings split by delimiters. A_LoopField is current substring.",
            Usage: "
(
• Loop Parse, str, delims
• A_LoopField = current part
• Multiple delimiters allowed
• No delim = each character
)",
            Code: "
(
; Parse CSV
csv := "apple,banana,cherry"
Loop Parse, csv, "," {
    MsgBox(A_Index . ": " . A_LoopField)
}

; Parse lines
text := "Line 1`nLine 2`nLine 3"
Loop Parse, text, "`n" {
    MsgBox("Line: " . A_LoopField)
}

; Each character
word := "Hello"
Loop Parse, word {
    MsgBox(A_LoopField)
}

; Build array
colors := "red,green,blue"
arr := []
Loop Parse, colors, "," {
    arr.Push(A_LoopField)
}
)"
        }
        
        this.data["ControlFlow_While Loop"] := {
            Name: "While Loop",
            Def: "Repeats while condition is true. Condition checked before each iteration. May execute zero times.",
            Usage: "
(
• while (condition) { ... }
• Checked before each iteration
• May never execute
• Don't forget to update condition!
)",
            Code: "
(
; Basic while
counter := 0
while (counter < 5) {
    MsgBox(counter)
    counter++
}

; Processing queue
queue := [1, 2, 3, 4, 5]
while (queue.Length > 0) {
    item := queue.RemoveAt(1)
    MsgBox("Processing: " . item)
}

; Infinite with break
while (true) {
    response := Random(1, 10)
    if (response = 7) {
        MsgBox("Lucky 7!")
        break
    }
}
)"
        }
        
        this.data["ControlFlow_For Loop"] := {
            Name: "For Loop",
            Def: "Iterates over collections (arrays, maps). Get value only, or index and value.",
            Usage: "
(
• for value in array
• for key, value in map
• for index, value in array
• Works with any enumerable
)",
            Code: "
(
; Array values
colors := ["red", "green", "blue"]
for color in colors {
    MsgBox(color)
}

; With index
for index, color in colors {
    MsgBox(index . ": " . color)
}

; Map
ages := Map("Alice", 30, "Bob", 25)
for name, age in ages {
    MsgBox(name . " is " . age)
}

; Sum array
numbers := [10, 20, 30, 40]
sum := 0
for num in numbers {
    sum += num
}
MsgBox("Sum: " . sum)
)"
        }
        
        this.data["ControlFlow_Break Continue"] := {
            Name: "Break and Continue",
            Def: "Break exits loop immediately. Continue skips to next iteration. Both can use labels for nested loops.",
            Usage: "
(
• break - exit loop
• continue - skip to next
• break label - exit labeled loop
• continue label - continue labeled loop
)",
            Code: "
(
; Break
Loop 10 {
    if (A_Index = 5) {
        break
    }
    MsgBox(A_Index)    ; 1, 2, 3, 4
}

; Continue
Loop 10 {
    if (Mod(A_Index, 2) = 0) {
        continue       ; Skip evens
    }
    MsgBox(A_Index)    ; 1, 3, 5, 7, 9
}

; Labeled break (nested loops)
outer:
Loop 3 {
    Loop 3 {
        if (A_Index = 2) {
            break outer   ; Exit outer loop
        }
    }
}
)"
        }
        
        this.data["ControlFlow_Try-Catch"] := {
            Name: "Try-Catch",
            Def: "Handle errors gracefully. Try block monitored; catch handles errors. Finally always runs.",
            Usage: "
(
• try { risky code }
• catch { handle error }
• catch as err { use err.Message }
• finally { cleanup }
)",
            Code: "
(
; Basic try-catch
try {
    result := 10 / 0
} catch {
    MsgBox("Error occurred")
}

; Catch with details
try {
    arr := []
    value := arr[100]
} catch as err {
    MsgBox("Error: " . err.Message)
}

; Finally
try {
    ; Code that might fail
} catch as err {
    MsgBox(err.Message)
} finally {
    MsgBox("Cleanup")
}

; Throw your own
Validate(age) {
    if (age < 0) {
        throw Error("Age cannot be negative")
    }
}

try {
    Validate(-5)
} catch as err {
    MsgBox(err.Message)
}
)"
        }
    }
    
    ; ──────────────────────────────────────────────────────────────────────────
    ; FUNCTIONS
    ; ──────────────────────────────────────────────────────────────────────────
    
    LoadFunctions() {
        this.data["Functions_Function Basics"] := {
            Name: "Function Definition",
            Def: "Functions are reusable code blocks. Defined with name, parameters in parens, body in braces.",
            Usage: "
(
• FunctionName(params) { ... }
• Call: FunctionName(args)
• return to send value back
• No return = empty string
)",
            Code: "
(
; Basic function
SayHello() {
    MsgBox("Hello!")
}
SayHello()

; With parameter
Greet(name) {
    MsgBox("Hello, " . name)
}
Greet("Alice")

; With return
Add(a, b) {
    return a + b
}
sum := Add(5, 3)
MsgBox(sum)

; Multiple statements
Calculate(x, y) {
    sum := x + y
    product := x * y
    return "Sum: " . sum . ", Product: " . product
}
)"
        }
        
        this.data["Functions_Parameters"] := {
            Name: "Function Parameters",
            Def: "Parameters receive values when called. Local to function. Passed by value (originals unchanged).",
            Usage: "
(
• Listed in parentheses
• Separated by commas
• Receive values in order
• Local to function
)",
            Code: "
(
; Multiple parameters
Format(name, age, city) {
    return name . " (" . age . ") from " . city
}
MsgBox(Format("Alice", 30, "NYC"))

; Parameters are local copies
value := 100
Change(value) {
    value := 999
}
Change(value)
MsgBox(value)    ; Still 100

; Array as parameter
Sum(arr) {
    total := 0
    for n in arr {
        total += n
    }
    return total
}
MsgBox(Sum([1, 2, 3]))

; ByRef to modify original
Double(&n) {
    n := n * 2
}
x := 5
Double(&x)
MsgBox(x)        ; 10
)"
        }
        
        this.data["Functions_Default Params"] := {
            Name: "Default Parameters",
            Def: "Default values used when argument omitted. Must come after required parameters.",
            Usage: "
(
• param := defaultValue
• Used when argument omitted
• Must be after required params
• Can use expressions
)",
            Code: "
(
Greet(name := "World") {
    MsgBox("Hello, " . name)
}
Greet("Alice")     ; Hello, Alice
Greet()            ; Hello, World

; Multiple defaults
CreateRect(w := 100, h := 50, color := "Black") {
    return {Width: w, Height: h, Color: color}
}

r1 := CreateRect()              ; All defaults
r2 := CreateRect(200)           ; 200, 50, Black
r3 := CreateRect(200, 100)      ; 200, 100, Black
r4 := CreateRect(200, 100, "Red")

; Required + optional
Send(to, subject, body := "") {
    ; to and subject required
    ; body optional
}
)"
        }
        
        this.data["Functions_Return Values"] := {
            Name: "Return Values",
            Def: "Functions send values back with return. Can return any type. Without return, empty string returned.",
            Usage: "
(
• return value - send to caller
• return - exit with ""
• Can return any type
• Multiple values via object
)",
            Code: "
(
; Return single value
Square(n) {
    return n * n
}
MsgBox(Square(5))    ; 25

; Return object for multiple values
Divide(a, b) {
    return {
        Quotient: a // b,
        Remainder: Mod(a, b)
    }
}
result := Divide(17, 5)
MsgBox("Q: " . result.Quotient . ", R: " . result.Remainder)

; Early return
GetGrade(score) {
    if (score >= 90)
        return "A"
    if (score >= 80)
        return "B"
    return "C"
}

; Success/error pattern
SafeDivide(a, b) {
    if (b = 0) {
        return {Ok: false, Error: "Div by zero"}
    }
    return {Ok: true, Value: a / b}
}
)"
        }
        
        this.data["Functions_Arrow Functions"] := {
            Name: "Arrow Functions (=>)",
            Def: "Concise anonymous functions. Single expression auto-returns result. Great for callbacks.",
            Usage: "
(
• () => expr - no params
• x => expr - one param
• (x, y) => expr - multiple
• Auto-returns expression
)",
            Code: "
(
; No parameters
getTime := () => A_Now
MsgBox(getTime())

; Single parameter
double := x => x * 2
MsgBox(double(5))      ; 10

; Multiple parameters
add := (a, b) => a + b
MsgBox(add(3, 4))      ; 7

; As callback
SetTimer(() => ToolTip("Tick"), 1000)

; In objects
calc := {
    add: (this, a, b) => a + b,
    mul: (this, a, b) => a * b
}
MsgBox(calc.add(5, 3)) ; 8

; Multi-line needs braces
complex := (x) => {
    result := x * 2
    return result + 10
}
)"
        }
        
        this.data["Functions_Closures"] := {
            Name: "Closures",
            Def: "Functions that capture variables from enclosing scope. Captured variables persist after outer function returns.",
            Usage: "
(
• Inner function captures outer vars
• Captured vars persist
• Each call creates new closure
• Enables factories and state
)",
            Code: "
(
; Multiplier factory
MakeMultiplier(factor) {
    return (n) => n * factor
}

double := MakeMultiplier(2)
triple := MakeMultiplier(3)
MsgBox(double(5))     ; 10
MsgBox(triple(5))     ; 15

; Counter
MakeCounter() {
    count := 0
    return () => {
        count++
        return count
    }
}

counter := MakeCounter()
MsgBox(counter())     ; 1
MsgBox(counter())     ; 2
MsgBox(counter())     ; 3

; Private state
CreateAccount(initial) {
    balance := initial
    return {
        Deposit: (amt) => balance += amt,
        GetBalance: () => balance
    }
}
)"
        }
        
        this.data["Functions_Callbacks"] := {
            Name: "Callbacks",
            Def: "Functions passed as arguments to be called later. Used for events, timers, and async patterns.",
            Usage: "
(
• Pass function as argument
• Called by receiving function
• Arrow functions work well
• Common in GUI events
)",
            Code: "
(
; Basic callback
Process(callback) {
    result := 42
    callback(result)
}
Process((x) => MsgBox("Got: " . x))

; SetTimer callback
SetTimer(() => ToolTip("Hello"), -1000)

; GUI event
myGui := Gui()
btn := myGui.AddButton(, "Click")
btn.OnEvent("Click", (*) => MsgBox("Clicked!"))
myGui.Show()

; Custom iteration
ForEach(arr, fn) {
    for item in arr {
        fn(item)
    }
}
ForEach([1, 2, 3], (x) => MsgBox(x))

; Filter pattern
Filter(arr, predicate) {
    result := []
    for item in arr {
        if (predicate(item)) {
            result.Push(item)
        }
    }
    return result
}
evens := Filter([1,2,3,4], n => Mod(n, 2) = 0)
)"
        }
    }
    
    ; ──────────────────────────────────────────────────────────────────────────
    ; CLASSES
    ; ──────────────────────────────────────────────────────────────────────────
    
    LoadClasses() {
        this.data["Classes_Class Basics"] := {
            Name: "Class Definition",
            Def: "Classes are blueprints for objects. Encapsulate properties (data) and methods (behavior). Create instances with ClassName().",
            Usage: "
(
• class Name { ... }
• Properties store data
• Methods define behavior
• Create: instance := ClassName()
• Access: instance.property
)",
            Code: "
(
class Person {
    Name := ""
    Age := 0
    
    Greet() {
        return "Hello, I'm " . this.Name
    }
    
    HaveBirthday() {
        this.Age++
    }
}

; Create instance
p := Person()
p.Name := "Alice"
p.Age := 30

MsgBox(p.Greet())
p.HaveBirthday()
MsgBox("Now " . p.Age)

; Multiple instances
p2 := Person()
p2.Name := "Bob"
; Each has own data
)"
        }
        
        this.data["Classes_Constructor"] := {
            Name: "Constructor (__New)",
            Def: "__New is called automatically when instance created. Use to initialize properties. Receives arguments from ClassName(args).",
            Usage: "
(
• __New(params) { ... }
• Called on instance creation
• Initialize properties here
• 'this' = new instance
)",
            Code: "
(
class User {
    Name := ""
    Email := ""
    Created := ""
    
    __New(name, email) {
        this.Name := name
        this.Email := email
        this.Created := A_Now
    }
}

user := User("Alice", "alice@test.com")
MsgBox(user.Name)    ; Alice

; With defaults
class Config {
    Host := ""
    Port := 0
    
    __New(host := "localhost", port := 8080) {
        this.Host := host
        this.Port := port
    }
}

c1 := Config()              ; localhost:8080
c2 := Config("api.com", 443)

; With validation
class PositiveNum {
    Value := 0
    
    __New(val) {
        if (val < 0) {
            throw Error("Must be positive")
        }
        this.Value := val
    }
}
)"
        }
        
        this.data["Classes_Properties"] := {
            Name: "Properties",
            Def: "Properties store data in instances. Declare with name and optional default. Each instance has its own copy.",
            Usage: "
(
• Declare: PropName := value
• Access: instance.PropName
• Assign: instance.PropName := x
• Each instance independent
)",
            Code: "
(
class Car {
    Make := ""
    Model := ""
    Year := 0
    Running := false
}

car := Car()
car.Make := "Toyota"
car.Model := "Camry"
car.Year := 2020

; Different instances
car2 := Car()
car2.Make := "Honda"
; car.Make still "Toyota"

; Array/object properties
class Playlist {
    Name := ""
    Songs := []
    
    __New(name) {
        this.Name := name
        this.Songs := []   ; New array per instance!
    }
    
    Add(song) {
        this.Songs.Push(song)
    }
}

pl := Playlist("My List")
pl.Add("Song 1")
)"
        }
        
        this.data["Classes_Methods"] := {
            Name: "Methods",
            Def: "Methods are functions in classes. Receive 'this' automatically. Called with instance.Method().",
            Usage: "
(
• Define inside class body
• 'this' refers to instance
• Access properties via this
• Return this for chaining
)",
            Code: "
(
class Calculator {
    Value := 0
    
    Add(n) {
        this.Value += n
        return this        ; For chaining
    }
    
    Multiply(n) {
        this.Value *= n
        return this
    }
    
    GetResult() {
        return this.Value
    }
    
    Reset() {
        this.Value := 0
        return this
    }
}

; Method chaining
calc := Calculator()
result := calc.Add(10).Multiply(2).Add(5).GetResult()
MsgBox(result)    ; 25

; Methods calling methods
class StringHelper {
    Text := ""
    
    __New(text) {
        this.Text := text
    }
    
    Upper() {
        return StrUpper(this.Text)
    }
    
    Info() {
        return "Text: " . this.Text . ", Upper: " . this.Upper()
    }
}
)"
        }
        
        this.data["Classes_Static Members"] := {
            Name: "Static Members",
            Def: "Static members belong to class, not instances. Shared across all instances. Access with ClassName.Member.",
            Usage: "
(
• static PropName := value
• Access: ClassName.Member
• Shared by all instances
• Good for constants, utilities
)",
            Code: "
(
class Counter {
    static Total := 0
    Id := 0
    
    __New() {
        Counter.Total++
        this.Id := Counter.Total
    }
    
    static GetTotal() {
        return Counter.Total
    }
}

c1 := Counter()    ; Id = 1
c2 := Counter()    ; Id = 2
c3 := Counter()    ; Id = 3

MsgBox("Total: " . Counter.GetTotal())   ; 3

; Static utility class
class MathUtils {
    static PI := 3.14159
    
    static CircleArea(r) {
        return MathUtils.PI * r * r
    }
}

MsgBox(MathUtils.CircleArea(5))
)"
        }
        
        this.data["Classes_Inheritance"] := {
            Name: "Inheritance (extends)",
            Def: "Child class inherits from parent. Gets parent's properties and methods. Can override and add new members.",
            Usage: "
(
• class Child extends Parent
• Inherits all parent members
• Override by redefining
• super.Method() calls parent
)",
            Code: "
(
class Animal {
    Name := ""
    
    __New(name) {
        this.Name := name
    }
    
    Speak() {
        return "..."
    }
}

class Dog extends Animal {
    Breed := ""
    
    __New(name, breed) {
        super.__New(name)  ; Call parent
        this.Breed := breed
    }
    
    Speak() {              ; Override
        return "Woof!"
    }
    
    Fetch() {              ; New method
        return this.Name . " fetches"
    }
}

class Cat extends Animal {
    Speak() {
        return "Meow!"
    }
}

dog := Dog("Rex", "Lab")
cat := Cat("Whiskers")

MsgBox(dog.Speak())    ; Woof!
MsgBox(cat.Speak())    ; Meow!
MsgBox(dog.Fetch())
)"
        }
        
        this.data["Classes_Property GetSet"] := {
            Name: "Property Get/Set",
            Def: "Custom logic when reading/writing properties. Get runs on read, Set on write. 'value' is the assigned value.",
            Usage: "
(
• Prop { get { return x } }
• Prop { set { this._x := value } }
• Read-only: get only
• Computed: calculate on access
)",
            Code: "
(
class Temperature {
    _celsius := 0
    
    Celsius {
        get => this._celsius
        set => this._celsius := value
    }
    
    ; Computed property
    Fahrenheit {
        get => this._celsius * 9/5 + 32
        set => this._celsius := (value - 32) * 5/9
    }
}

t := Temperature()
t.Celsius := 100
MsgBox(t.Fahrenheit)   ; 212

t.Fahrenheit := 32
MsgBox(t.Celsius)      ; 0

; Validation in setter
class Person {
    _age := 0
    
    Age {
        get => this._age
        set {
            if (value < 0 || value > 150) {
                throw Error("Invalid age")
            }
            this._age := value
        }
    }
}
)"
        }
    }
}

; ══════════════════════════════════════════════════════════════════════════════
; LAUNCH
; ══════════════════════════════════════════════════════════════════════════════

app := CompleteReferenceApp()
