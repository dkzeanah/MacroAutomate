; =====================================================================================
; GLOBALCODER - Comprehensive Menu & Automation System
; AutoHotkey v2.0 - Teaching Edition with Project Management
; =====================================================================================
; FEATURES:
; - File-based step loading for extensible project tutorials
; - Multiple project setup pathways per language
; - Arrow key navigation in StepCanvas
; - GUT-Display for transparent notifications
; - Comprehensive .NET, JavaScript, Python, TypeScript support
; =====================================================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#ErrorStdOut

; =====================================================================================
; SECTION 1: GLOBAL VARIABLES & PATHS
; =====================================================================================

global mainMenu := ""
global TotalWords := 0
global items := 0
global callingWindowTitle := ""
global callingWindowItem := ""

; Path definitions
global CustomMenuPath := A_ScriptDir "\CustomMenuFiles"
global LogsPath := CustomMenuPath "\logs"
global NotesPath := CustomMenuPath "\notes"
global ClassesPath := NotesPath "\classes"
global SnipsPath := CustomMenuPath "\0_snips"
global ProjectsPath := CustomMenuPath "\1_projects"
global SettingsFile := CustomMenuPath "\settings.ini"
global ActionsFile := CustomMenuPath "\actions.ini"
global StepFilesPath := CustomMenuPath "\step_definitions"  ; NEW: Central step files location

; Project management paths
global DefaultProjectRoot := "D:\code"
global VSCodePath := "code"
global SublimePath := "C:\Program Files\Sublime Text\sublime_text.exe"
global GitBashPath := "C:\Program Files\Git\git-bash.exe"
global TemplatesPath := CustomMenuPath "\templates"

; GUT-Display defaults
global GUT_DefaultTimeout := 5000
global GUT_DefaultTransparency := 180
global GUT_DefaultWidth := 500
global GUT_DefaultHeight := 300

; Active StepCanvas reference for hotkey handling
global activeStepCanvas := ""

; =====================================================================================
; SECTION 2: INITIALIZATION
; =====================================================================================

InitializeSettings()
InitializeFolderStructure()
SetupTrayMenu()
mainMenu := PrepareMenu(CustomMenuPath)
OnError(LogError)
Return

; =====================================================================================
; SECTION 3: INITIALIZATION FUNCTIONS
; =====================================================================================

InitializeSettings() {
    global SettingsFile, GUT_DefaultTimeout, GUT_DefaultTransparency
    global GUT_DefaultWidth, GUT_DefaultHeight, CustomMenuPath
    global DefaultProjectRoot, VSCodePath, SublimePath, GitBashPath

    if (!DirExist(CustomMenuPath)) {
        DirCreate(CustomMenuPath)
    }

    if (!FileExist(SettingsFile)) {
        IniWrite(5000, SettingsFile, "GUT_Display", "Timeout")
        IniWrite(180, SettingsFile, "GUT_Display", "Transparency")
        IniWrite(500, SettingsFile, "GUT_Display", "DefaultWidth")
        IniWrite(300, SettingsFile, "GUT_Display", "DefaultHeight")
        IniWrite("TopRight", SettingsFile, "GUT_Display", "Position")

        IniWrite(1, SettingsFile, "General", "ShowTooltips")
        IniWrite(2000, SettingsFile, "General", "TooltipDuration")
        IniWrite(1, SettingsFile, "General", "LogUsage")

        IniWrite("D:\code", SettingsFile, "Projects", "DefaultRoot")
        IniWrite("code", SettingsFile, "Projects", "VSCodePath")
        IniWrite("C:\Program Files\Sublime Text\sublime_text.exe", SettingsFile, "Projects", "SublimePath")
        IniWrite("C:\Program Files\Git\git-bash.exe", SettingsFile, "Projects", "GitBashPath")
    }

    GUT_DefaultTimeout := Integer(IniRead(SettingsFile, "GUT_Display", "Timeout", 5000))
    GUT_DefaultTransparency := Integer(IniRead(SettingsFile, "GUT_Display", "Transparency", 180))
    GUT_DefaultWidth := Integer(IniRead(SettingsFile, "GUT_Display", "DefaultWidth", 500))
    GUT_DefaultHeight := Integer(IniRead(SettingsFile, "GUT_Display", "DefaultHeight", 300))

    DefaultProjectRoot := IniRead(SettingsFile, "Projects", "DefaultRoot", "D:\code")
    VSCodePath := IniRead(SettingsFile, "Projects", "VSCodePath", "code")
    SublimePath := IniRead(SettingsFile, "Projects", "SublimePath", "C:\Program Files\Sublime Text\sublime_text.exe")
    GitBashPath := IniRead(SettingsFile, "Projects", "GitBashPath", "C:\Program Files\Git\git-bash.exe")
}

InitializeFolderStructure() {
    global CustomMenuPath, LogsPath, NotesPath, ClassesPath, SnipsPath
    global ProjectsPath, TemplatesPath, StepFilesPath

    ; Create all required directories
    requiredDirs := [
        CustomMenuPath,
        LogsPath,
        NotesPath,
        ClassesPath,
        SnipsPath,
        SnipsPath "\python",
        SnipsPath "\csharp",
        SnipsPath "\javascript",
        SnipsPath "\autohotkey",
        SnipsPath "\typescript",
        ProjectsPath,
        TemplatesPath,
        TemplatesPath "\.vscode",
        StepFilesPath,
        StepFilesPath "\javascript",
        StepFilesPath "\python",
        StepFilesPath "\csharp",
        StepFilesPath "\typescript"
    ]

    for index, dirPath in requiredDirs {
        if (!DirExist(dirPath)) {
            DirCreate(dirPath)
        }
    }

    ; Create step definition files if they don't exist
    CreateStepDefinitionFiles()

    ; Create VSCode templates
    CreateVSCodeTemplates()

    ; Initialize actions file
    InitializeActionsFile()
}

CreateStepDefinitionFiles() {
    ; ---------------------------------------------------------------------------------
    ; Purpose: Create the step definition files for each language
    ; These are external files that can be edited to add more project types
    ; ---------------------------------------------------------------------------------
    global StepFilesPath

    ; Check if JS steps file exists, if not create it
    jsStepsFile := StepFilesPath "\javascript\projects.steps"
    if (!FileExist(jsStepsFile)) {
        CreateJavaScriptStepsFile(jsStepsFile)
    }

    ; Python steps file
    pyStepsFile := StepFilesPath "\python\projects.steps"
    if (!FileExist(pyStepsFile)) {
        CreatePythonStepsFile(pyStepsFile)
    }

    ; C# steps file
    csStepsFile := StepFilesPath "\csharp\projects.steps"
    if (!FileExist(csStepsFile)) {
        CreateCSharpStepsFile(csStepsFile)
    }

    ; TypeScript steps file
    tsStepsFile := StepFilesPath "\typescript\projects.steps"
    if (!FileExist(tsStepsFile)) {
        CreateTypeScriptStepsFile(tsStepsFile)
    }
}

CreateJavaScriptStepsFile(filePath) {
    ; ---------------------------------------------------------------------------------
    ; JavaScript Project Steps - Comprehensive teaching file
    ; Format: [ProjectType] header followed by pipe-delimited steps
    ; step|command|directions|input_needed|explanation
    ; ---------------------------------------------------------------------------------

    content := "
(
; =====================================================================================
; JAVASCRIPT PROJECT SETUP STEPS
; =====================================================================================
; Format: step|command|directions|input_needed|explanation
; Lines starting with ; are comments
; [ProjectType] starts a new project type section
; Empty lines are ignored
; =====================================================================================

[Vanilla JS Static Site]
; Pure vanilla JS - no Node, just a static site you can serve locally
1|mkdir VanillaStatic && cd VanillaStatic|Create project folder|Folder name|Creates and enters your project directory
2|New-Item index.html -ItemType File|Create HTML file (PowerShell)|None|PowerShell command to create empty file
3|New-Item main.js -ItemType File|Create JS file (PowerShell)|None|Creates your main JavaScript file
4|code .|Open in VS Code|None|Opens folder in Visual Studio Code
5|npx serve .|Start local server|None|Uses npx to run serve without installing globally

[Node + Express API]
; Basic Node.js Express server - good for APIs and backends
1|mkdir NodeApi && cd NodeApi|Create project folder|Project name|Creates your API project directory
2|npm init -y|Initialize package.json|None|Creates default package.json with project metadata
3|npm install express|Install Express framework|None|Adds Express.js web framework to your project
4|New-Item index.js -ItemType File|Create entry point|None|Creates the main server file
5|code .|Open in VS Code|None|Opens folder to add server code
6|npm run dev|Start the server|None|Runs the dev script (add ""dev"": ""node index.js"" to package.json scripts)

[React with Vite]
; Modern React setup using Vite bundler - fast and lightweight
1|npm create vite@latest my-react-app -- --template react|Create React project|App name|Vite scaffolds a complete React application
2|cd my-react-app|Enter project directory|None|Navigate into the created project folder
3|npm install|Install dependencies|None|Downloads all required packages from package.json
4|npm run dev|Start development server|None|Launches Vite dev server with hot reload
5|Open http://localhost:5173/|View in browser|None|Default Vite port is 5173, not 3000

[React + TypeScript with Vite]
; React with TypeScript for type safety
1|npm create vite@latest my-react-ts-app -- --template react-ts|Create React+TS project|App name|Scaffolds React with TypeScript configuration
2|cd my-react-ts-app|Enter project directory|None|Navigate into the created project folder
3|npm install|Install dependencies|None|Downloads packages including TypeScript types
4|npm run dev|Start development server|None|Launches dev server with TypeScript compilation
5|Open http://localhost:5173/|View in browser|None|Your TypeScript React app is now running

[Next.js App]
; Full-stack React framework with server-side rendering
1|npx create-next-app@latest my-next-app|Create Next.js project|App name + options|Interactive wizard asks about TypeScript, Tailwind, etc.
2|cd my-next-app|Enter project directory|None|Navigate into the created project folder
3|npm run dev|Start development server|None|Launches Next.js dev server
4|Open http://localhost:3000/|View in browser|None|Next.js uses port 3000 by default

[Vite + React + TypeScript + Tailwind]
; Full modern stack with utility-first CSS
1|npm create vite@latest my-vite-tailwind -- --template react-ts|Create Vite+React+TS|App name|Base project with TypeScript
2|cd my-vite-tailwind|Enter project directory|None|Navigate into the project
3|npm install|Install base dependencies|None|Downloads React and TypeScript packages
4|npm install -D tailwindcss postcss autoprefixer|Install Tailwind|None|Adds Tailwind CSS and its dependencies
5|npx tailwindcss init -p|Initialize Tailwind config|None|Creates tailwind.config.js and postcss.config.js
6|Edit tailwind.config.js|Configure content paths|See explanation|Add: content: ['./index.html', './src/**/*.{js,ts,jsx,tsx}']
7|Edit src/index.css|Add Tailwind directives|None|Replace with: @tailwind base; @tailwind components; @tailwind utilities;
8|npm run dev|Start development server|None|Tailwind classes now work in your components

[Vanilla TypeScript + Tailwind]
; TypeScript without React, with Tailwind styling
1|mkdir vanilla-ts-tailwind && cd vanilla-ts-tailwind|Create project folder|Folder name|Creates your project directory
2|npm init -y|Initialize package.json|None|Creates default package.json
3|npm install -D typescript vite tailwindcss postcss autoprefixer|Install dev dependencies|None|All tooling as dev dependencies
4|npx tsc --init|Create tsconfig.json|None|Initializes TypeScript configuration
5|npx tailwindcss init -p|Initialize Tailwind|None|Creates Tailwind configuration files
6|Create index.html and src/main.ts|Create entry files|None|Manual file creation for entry points
7|npm run dev|Start Vite dev server|None|Add ""dev"": ""vite"" to package.json scripts first

[Express + TypeScript API]
; Type-safe backend development
1|mkdir express-ts-api && cd express-ts-api|Create project folder|Folder name|Creates your API project directory
2|npm init -y|Initialize package.json|None|Creates default package.json
3|npm install express|Install Express|None|Adds Express.js framework
4|npm install -D typescript @types/express @types/node ts-node nodemon|Install dev deps|None|TypeScript tooling and type definitions
5|npx tsc --init|Create tsconfig.json|None|Initializes TypeScript configuration
6|Create src/index.ts|Create entry point|None|Your main server file in TypeScript
7|npm run dev|Start with nodemon|None|Add script: ""dev"": ""nodemon --exec ts-node src/index.ts""
)"

    FileAppend(content, filePath)
}

CreatePythonStepsFile(filePath) {
    ; ---------------------------------------------------------------------------------
    ; Python Project Steps - Multiple environment management approaches
    ; ---------------------------------------------------------------------------------

    content := "
(
; =====================================================================================
; PYTHON PROJECT SETUP STEPS
; =====================================================================================
; Format: step|command|directions|input_needed|explanation
; Multiple approaches: venv, conda, poetry, pipenv
; =====================================================================================

[Python venv (Standard)]
; Built-in Python virtual environment - no extra tools needed
1|mkdir MyPythonProject && cd MyPythonProject|Create project folder|Project name|Creates your project directory
2|python -m venv venv|Create virtual environment|None|Creates isolated Python environment in ./venv folder
3|venv\Scripts\activate|Activate environment (Windows)|None|Activates venv - prompt shows (venv) prefix
4|source venv/bin/activate|Activate environment (Mac/Linux)|None|Alternative activation for Unix systems
5|pip install --upgrade pip|Upgrade pip|None|Ensures you have the latest pip version
6|pip install <package>|Install packages|Package names|Install packages like: pip install requests flask
7|pip freeze > requirements.txt|Save dependencies|None|Creates requirements.txt listing all installed packages
8|deactivate|Exit virtual environment|None|Returns to system Python

[Anaconda/Miniconda]
; Data science focused - great for numpy, pandas, jupyter
1|conda create -n myenv python=3.11|Create conda environment|Env name, Python version|Creates isolated conda environment
2|conda activate myenv|Activate environment|None|Activates the conda environment
3|conda install numpy pandas matplotlib|Install data science packages|Package names|Conda handles complex dependencies well
4|conda install jupyter|Install Jupyter|None|Adds Jupyter notebooks support
5|jupyter notebook|Start Jupyter|None|Opens Jupyter in your browser
6|conda env export > environment.yml|Export environment|None|Creates portable environment definition
7|conda deactivate|Exit environment|None|Returns to base conda environment

[Poetry (Modern Dependency Management)]
; Modern Python packaging and dependency management
1|pip install poetry|Install Poetry|None|One-time global installation of Poetry
2|poetry new my-project|Create new project|Project name|Creates project with proper structure
3|cd my-project|Enter project directory|None|Navigate into the created project
4|poetry add requests|Add a dependency|Package name|Adds package and updates pyproject.toml
5|poetry add pytest --group dev|Add dev dependency|Package name|Adds development-only dependencies
6|poetry install|Install all dependencies|None|Installs everything from pyproject.toml
7|poetry shell|Activate environment|None|Enters the Poetry-managed virtual environment
8|poetry run python main.py|Run without activating|Script name|Runs Python in the environment without activating

[Pipenv]
; Combines pip and virtualenv into one tool
1|pip install pipenv|Install Pipenv|None|One-time global installation of Pipenv
2|mkdir myproject && cd myproject|Create project folder|Project name|Creates your project directory
3|pipenv install|Create environment|None|Creates Pipfile and virtual environment
4|pipenv install requests flask|Install packages|Package names|Adds packages to Pipfile automatically
5|pipenv install pytest --dev|Install dev packages|Package name|Separates dev dependencies
6|pipenv shell|Activate environment|None|Enters the Pipenv shell
7|pipenv run python app.py|Run without shell|Script name|Runs in environment without activating
8|pipenv lock|Generate lockfile|None|Creates Pipfile.lock for reproducible installs

[Python Fundamentals - Syntax Basics]
; Learning path for Python syntax (reference, not project setup)
1|# Variables and Types|x = 5, name = ""hello"", is_valid = True|None|Python uses dynamic typing - no type declarations needed
2|# Lists|my_list = [1, 2, 3], my_list.append(4)|None|Ordered, mutable sequences - use [] syntax
3|# Dictionaries|my_dict = {""key"": ""value""}|None|Key-value pairs - use {} syntax
4|# Functions|def greet(name): return f""Hello {name}""|None|Use def keyword, indentation defines scope
5|# Loops|for item in items: print(item)|None|For loops iterate over iterables directly
6|# Conditionals|if x > 5: elif x == 5: else:|None|Colons and indentation, no braces needed
7|# Classes|class Dog: def __init__(self, name):|None|Use class keyword, __init__ is constructor
8|# Imports|import os, from pathlib import Path|None|Import modules or specific items from modules
)"

    FileAppend(content, filePath)
}

CreateCSharpStepsFile(filePath) {
    ; ---------------------------------------------------------------------------------
    ; C# / .NET Project Steps
    ; ---------------------------------------------------------------------------------

    content := "
(
; =====================================================================================
; C# / .NET PROJECT SETUP STEPS
; =====================================================================================
; Format: step|command|directions|input_needed|explanation
; =====================================================================================

[.NET Console App]
; Basic console application
1|dotnet new console -n MyConsoleApp|Create console project|Project name|Scaffolds a C# console application
2|cd MyConsoleApp|Enter project directory|None|Navigate into the created project
3|dotnet restore|Restore NuGet packages|None|Downloads any dependencies
4|dotnet build|Build the project|None|Compiles the application
5|dotnet run|Run the application|None|Executes the compiled application

[.NET Class Library]
; Reusable code library
1|dotnet new classlib -n MyLibrary|Create class library|Library name|Creates a reusable library project
2|cd MyLibrary|Enter project directory|None|Navigate into the created project
3|dotnet build|Build the library|None|Compiles to a .dll file

[.NET Solution with Console + Library]
; Full solution structure (recommended for larger projects)
1|mkdir MySolution && cd MySolution|Create solution folder|Solution name|Creates root directory for solution
2|dotnet new sln -n MySolution|Create solution file|Solution name|Creates .sln file to organize projects
3|dotnet new console -n MyApp|Create console project|App name|Creates the main application
4|dotnet new classlib -n MyLibrary|Create class library|Library name|Creates reusable code library
5|dotnet sln MySolution.sln add **/*.csproj|Add projects to solution|None|Wildcard adds all .csproj files found
6|dotnet add MyApp/MyApp.csproj reference MyLibrary/MyLibrary.csproj|Add project reference|None|Links library to console app
7|dotnet restore|Restore all packages|None|Downloads dependencies for all projects
8|dotnet build|Build entire solution|None|Compiles all projects
9|dotnet run --project MyApp|Run the application|Project path|Runs the console app

[.NET Web API]
; RESTful API backend
1|dotnet new webapi -n MyApi|Create Web API project|API name|Scaffolds ASP.NET Core Web API
2|cd MyApi|Enter project directory|None|Navigate into the created project
3|dotnet restore|Restore packages|None|Downloads ASP.NET Core dependencies
4|dotnet run|Start the API|None|Launches on https://localhost:5001
5|Open https://localhost:5001/swagger|View Swagger UI|None|Interactive API documentation

[.NET Blazor WebAssembly]
; Client-side web app with C#
1|dotnet new blazorwasm -n MyBlazorApp|Create Blazor WASM project|App name|C# running in the browser via WebAssembly
2|cd MyBlazorApp|Enter project directory|None|Navigate into the created project
3|dotnet run|Start development server|None|Launches Blazor app
4|Open https://localhost:5001|View in browser|None|Your Blazor app is now running
)"

    FileAppend(content, filePath)
}

CreateTypeScriptStepsFile(filePath) {
    ; ---------------------------------------------------------------------------------
    ; TypeScript Project Steps
    ; ---------------------------------------------------------------------------------

    content := "
(
; =====================================================================================
; TYPESCRIPT PROJECT SETUP STEPS
; =====================================================================================
; Format: step|command|directions|input_needed|explanation
; =====================================================================================

[TypeScript Node Project]
; Basic TypeScript for Node.js
1|mkdir ts-node-project && cd ts-node-project|Create project folder|Folder name|Creates your project directory
2|npm init -y|Initialize package.json|None|Creates default package.json
3|npm install typescript --save-dev|Install TypeScript|None|Adds TypeScript compiler as dev dependency
4|npx tsc --init|Create tsconfig.json|None|Initializes TypeScript configuration
5|mkdir src && New-Item src/index.ts -ItemType File|Create source folder and entry|None|Sets up source directory structure
6|npx tsc|Compile TypeScript|None|Compiles .ts files to .js based on tsconfig
7|node dist/index.js|Run compiled code|None|Executes the JavaScript output

[TypeScript with ts-node (No Compile Step)]
; Run TypeScript directly without pre-compiling
1|mkdir ts-direct && cd ts-direct|Create project folder|Folder name|Creates your project directory
2|npm init -y|Initialize package.json|None|Creates default package.json
3|npm install typescript ts-node @types/node --save-dev|Install dependencies|None|ts-node runs TS directly
4|npx tsc --init|Create tsconfig.json|None|Initializes TypeScript configuration
5|Create src/index.ts|Create entry point|None|Your main TypeScript file
6|npx ts-node src/index.ts|Run directly|None|Executes TypeScript without compiling first

[TypeScript + ESLint + Prettier]
; Professional TypeScript setup with linting and formatting
1|mkdir ts-pro && cd ts-pro|Create project folder|Folder name|Creates your project directory
2|npm init -y|Initialize package.json|None|Creates default package.json
3|npm install typescript --save-dev|Install TypeScript|None|TypeScript compiler
4|npm install eslint @typescript-eslint/parser @typescript-eslint/eslint-plugin --save-dev|Install ESLint|None|Linting for TypeScript
5|npm install prettier eslint-config-prettier --save-dev|Install Prettier|None|Code formatting
6|npx tsc --init|Create tsconfig.json|None|TypeScript configuration
7|Create .eslintrc.js|Configure ESLint|None|Set up linting rules
8|Create .prettierrc|Configure Prettier|None|Set up formatting rules
)"

    FileAppend(content, filePath)
}

CreateVSCodeTemplates() {
    global TemplatesPath

    vscodeDir := TemplatesPath "\.vscode"
    if (!DirExist(vscodeDir)) {
        DirCreate(vscodeDir)
    }

    ; launch.json template
    launchJson := '
(
{
    "version": "0.2.0",
    "configurations": [
        {
            "name": ".NET Core Launch (console)",
            "type": "coreclr",
            "request": "launch",
            "preLaunchTask": "build",
            "program": "${workspaceFolder}/bin/Debug/net8.0/${workspaceFolderBasename}.dll",
            "args": [],
            "cwd": "${workspaceFolder}",
            "console": "internalConsole",
            "stopAtEntry": false
        }
    ]
}
)'
    if (!FileExist(vscodeDir "\launch.json")) {
        FileAppend(launchJson, vscodeDir "\launch.json")
    }

    ; tasks.json template
    tasksJson := '
(
{
    "version": "2.0.0",
    "tasks": [
        {
            "label": "build",
            "command": "dotnet",
            "type": "process",
            "args": ["build", "${workspaceFolder}"],
            "problemMatcher": "$msCompile"
        }
    ]
}
)'
    if (!FileExist(vscodeDir "\tasks.json")) {
        FileAppend(tasksJson, vscodeDir "\tasks.json")
    }
}

InitializeActionsFile()


/*
InitializeActionsFile() {
    global ActionsFile

    if (!FileExist(ActionsFile)) {
        actionsContent := "
(
[Actions]
Dump Clipboard=Action_DumpClipboard
New Folder=Action_NewFolder
New File=Action_NewFile
Open in Explorer=Action_OpenFolder
Capture Structure=Action_CaptureStructure

[ActionDescriptions]
Dump Clipboard=Append clipboard contents with timestamp to a dump file
New Folder=Create a new subfolder in this location
New File=Create a new file, optionally with clipboard content
Open in Explorer=Open this folder in Windows Explorer
Capture Structure=Generate a text representation of the folder tree
)"
        FileAppend(actionsContent, ActionsFile)
    }
}

; =====================================================================================
; SECTION 4: STEP FILE LOADER - Parses .steps files into project types
; =====================================================================================

class StepFileLoader {
    ; ---------------------------------------------------------------------------------
    ; Purpose: Load and parse .steps files into structured data
    ; Returns: Map of project types, each containing array of step Maps
    ; ---------------------------------------------------------------------------------

    static LoadFile(filePath) {
        ; Returns a Map where:
        ; Key = Project type name (e.g., "Vanilla JS Static Site")
        ; Value = Array of step Maps (step, command, directions, input, explanation)

        projectTypes := Map()

        if (!FileExist(filePath)) {
            return projectTypes
        }

        try {
            fileContent := FileRead(filePath)
        } catch {
            return projectTypes
        }

        currentType := ""
        currentSteps := []

        ; Parse line by line
        for lineText in StrSplit(fileContent, "`n", "`r") {
            lineText := Trim(lineText)

            ; Skip empty lines and comments
            if (lineText = "" || SubStr(lineText, 1, 1) = ";") {
                continue
            }

            ; Check for project type header [ProjectType]
            if (SubStr(lineText, 1, 1) = "[" && SubStr(lineText, -1) = "]") {
                ; Save previous project type if exists
                if (currentType != "" && currentSteps.Length > 0) {
                    projectTypes[currentType] := currentSteps
                }

                ; Start new project type
                currentType := SubStr(lineText, 2, StrLen(lineText) - 2)
                currentSteps := []
                continue
            }

            ; Parse step line (pipe-delimited)
            if (InStr(lineText, "|")) {
                parts := StrSplit(lineText, "|")

                if (parts.Length >= 5) {
                    stepData := Map(
                        "step", Trim(parts[1]),
                        "command", Trim(parts[2]),
                        "directions", Trim(parts[3]),
                        "input", Trim(parts[4]),
                        "explanation", Trim(parts[5])
                    )
                    currentSteps.Push(stepData)
                }
            }
        }

        ; Save last project type
        if (currentType != "" && currentSteps.Length > 0) {
            projectTypes[currentType] := currentSteps
        }

        return projectTypes
    }

    static GetProjectTypeNames(filePath) {
        ; Returns array of project type names from a .steps file
        projectTypes := this.LoadFile(filePath)
        names := []
        for typeName, steps in projectTypes {
            names.Push(typeName)
        }
        return names
    }

    static GetStepsForType(filePath, typeName) {
        ; Returns array of steps for a specific project type
        projectTypes := this.LoadFile(filePath)
        if (projectTypes.Has(typeName)) {
            return projectTypes[typeName]
        }
        return []
    }
}
*/

; =====================================================================================
; SECTION 5: TRAY MENU SETUP
; =====================================================================================

SetupTrayMenu() {
    A_TrayMenu.Delete()

    A_TrayMenu.Add("&Settings", (*) => ShowSettingsGUI())
    A_TrayMenu.Add("&Add Action Item", (*) => ShowAddActionGUI())
    A_TrayMenu.Add()

    ; Project Management submenu
    projectSubMenu := Menu()
    projectSubMenu.Add("Create New Project", (*) => ShowNewProjectWizard())
    projectSubMenu.Add("Open Recent Projects", (*) => ShowRecentProjects())
    projectSubMenu.Add()
    projectSubMenu.Add("📚 Learning Center", (*) => ShowLearningCenter())
    projectSubMenu.Add()
    projectSubMenu.Add("Project Settings", (*) => ShowProjectSettings())
    A_TrayMenu.Add("&Project Management", projectSubMenu)

    A_TrayMenu.Add()

    ; Demos submenu
    demoSubMenu := Menu()
    demoSubMenu.Add("GUT-Display Demo", (*) => DemoGUTDisplay())
    demoSubMenu.Add("Step Canvas Demo", (*) => DemoStepCanvas())
    demoSubMenu.Add("Project Steps Browser", (*) => ShowProjectStepsBrowser())
    A_TrayMenu.Add("&Demos && Showcases", demoSubMenu)

    A_TrayMenu.Add()
    A_TrayMenu.Add("Open &Script Folder", (*) => Run("explorer.exe " . A_ScriptDir))
    A_TrayMenu.Add("Open &Menu Folder", (*) => Run("explorer.exe " . CustomMenuPath))

    A_TrayMenu.Add()

    ; Original AHK tray menu
    originalTraySubMenu := Menu()
    originalTraySubMenu.Add("&Pause Script", (*) => Pause(-1))
    originalTraySubMenu.Add("&Suspend Hotkeys", (*) => Suspend(-1))
    originalTraySubMenu.Add()
    originalTraySubMenu.Add("&Open Script in Editor", (*) => Edit())
    originalTraySubMenu.Add("&Help", (*) => Run("https://www.autohotkey.com/docs/v2/"))
    A_TrayMenu.Add("&Original AHK Menu", originalTraySubMenu)

    A_TrayMenu.Add()
    A_TrayMenu.Add("&Reload Script", (*) => Reload())
    A_TrayMenu.Add("E&xit", (*) => ExitApp())

    A_TrayMenu.Default := "&Settings"
    A_IconTip := "GlobalCoder - Double-click for features, Right-click for admin"

    OnMessage(0x404, TrayIconCallback)
}

TrayIconCallback(wParam, lParam, msg, hwnd) {
    if (lParam = 0x203) {
        ShowMainFeaturesGUI()
        return 0
    }
}

; =====================================================================================
; SECTION 6: GUT-DISPLAY (Global Universal Transparent Display)
; =====================================================================================

GUT_Display(title := "Information", content := "", timeout := 0, options := Map()) {
    global GUT_DefaultTimeout, GUT_DefaultTransparency, GUT_DefaultWidth, GUT_DefaultHeight

    actualTimeout := (timeout = 0) ? GUT_DefaultTimeout : timeout
    width := options.Has("width") ? options["width"] : GUT_DefaultWidth
    height := options.Has("height") ? options["height"] : GUT_DefaultHeight
    transparency := options.Has("transparency") ? options["transparency"] : GUT_DefaultTransparency
    position := options.Has("position") ? options["position"] : "TopRight"

    gutGui := Gui("+AlwaysOnTop -Caption +ToolWindow +Border", "GUT_" . A_TickCount)
    gutGui.Opt("+E0x08000000")
    gutGui.BackColor := "1E1E1E"

    ; Store content for copy functionality
    if (Type(content) = "Array") {
        contentStr := ""
        for idx, item in content {
            if (Type(item) = "Map") {
                contentStr .= (idx > 1 ? "`n" : "") . (item.Has("text") ? item["text"] : "")
            } else {
                contentStr .= (idx > 1 ? "`n" : "") . String(item)
            }
        }
        gutGui.originalContent := contentStr
    } else {
        gutGui.originalContent := String(content)
    }

    gutGui.isAlwaysOnTop := true

    ; Title bar
    titleText := gutGui.Add("Text", "x5 y5 w" . (width - 10) . " h20 c00AAFF", "📋 " . title)
    titleText.SetFont("s10 bold")

    gutGui.Add("Text", "x5 y28 w" . (width - 10) . " h1 Background444444")

    contentHeight := height - 85

    if (options.Has("itemized") && options["itemized"] && Type(content) = "Array") {
        DisplayItemizedContent(gutGui, content, width, contentHeight, options)
    } else if (options.Has("tree") && options["tree"]) {
        DisplayTreeContent(gutGui, content, width, contentHeight)
    } else {
        editCtrl := gutGui.Add("Edit", "x5 y32 w" . (width - 10) . " h" . contentHeight
            . " +ReadOnly -E0x200 Background252526 cD4D4D4 +VScroll", gutGui.originalContent)
        editCtrl.SetFont("s9", "Consolas")
    }

    ; Bottom toolbar
    toolbarY := height - 45
    gutGui.Add("Text", "x5 y" . (toolbarY - 5) . " w" . (width - 10) . " h1 Background444444")

    btnCopy := gutGui.Add("Button", "x10 y" . toolbarY . " w70 h30", "📋 Copy")
    btnCopy.OnEvent("Click", (*) => CopyGUTContent(gutGui))

    btnX := 90
    if (options.Has("actions") && Type(options["actions"]) = "Array") {
        for index, action in options["actions"] {
            if (btnX + 80 < width - 170) {
                if (Type(action) = "Map" && action.Has("text") && action.Has("callback")) {
                    btn := gutGui.Add("Button", "x" . btnX . " y" . toolbarY . " w70 h30", action["text"])
                    btn.OnEvent("Click", action["callback"])
                    btnX += 80
                }
            }
        }
    }

    btnPin := gutGui.Add("Button", "x" . (width - 160) . " y" . toolbarY . " w70 h30 vPinBtn", "📌 Pin")
    btnPin.OnEvent("Click", (*) => ToggleGUTAlwaysOnTop(gutGui))

    btnClose := gutGui.Add("Button", "x" . (width - 80) . " y" . toolbarY . " w70 h30", "✖ Close")
    btnClose.OnEvent("Click", (*) => SafeDestroyGui(gutGui))

    if (actualTimeout > 0) {
        timeoutSecs := Round(actualTimeout / 1000)
        gutGui.Add("Text", "x" . (width - 90) . " y" . (toolbarY - 18) . " w80 h15 c666666 Right", "Auto: " . timeoutSecs . "s")
    }

    ; Position calculation
    MonitorGet(MonitorGetPrimary(), &left, &top, &right, &bottom)
    switch position {
        case "TopRight":
            posX := right - width - 10
            posY := top + 10
        case "TopLeft":
            posX := left + 10
            posY := top + 10
        case "BottomRight":
            posX := right - width - 10
            posY := bottom - height - 50
        case "BottomLeft":
            posX := left + 10
            posY := bottom - height - 50
        case "Center":
            posX := (right - left - width) // 2
            posY := (bottom - top - height) // 2
        default:
            posX := right - width - 10
            posY := top + 10
    }

    gutGui.Show("x" . posX . " y" . posY . " w" . width . " h" . height . " NoActivate")
    WinSetTransparent(transparency, "ahk_id " . gutGui.Hwnd)

    if (actualTimeout > 0) {
        SetTimer((*) => SafeDestroyGui(gutGui), -actualTimeout)
    }

    gutGui.timeout := actualTimeout
    return gutGui
}

ToggleGUTAlwaysOnTop(guiObj) {
    try {
        if (guiObj.isAlwaysOnTop) {
            guiObj.Opt("-AlwaysOnTop")
            guiObj.isAlwaysOnTop := false
            guiObj["PinBtn"].Text := "📍 Unpin"
            ToolTip("Window unpinned")
        } else {
            guiObj.Opt("+AlwaysOnTop")
            guiObj.isAlwaysOnTop := true
            guiObj["PinBtn"].Text := "📌 Pin"
            ToolTip("Window pinned")
        }
        SetTimer((*) => ToolTip(), -1500)
    }
}

SafeDestroyGui(guiObj) {
    try {
        if (IsObject(guiObj) && guiObj.HasProp("Hwnd")) {
            hwnd := guiObj.Hwnd
            if (WinExist("ahk_id " . hwnd)) {
                guiObj.Destroy()
            }
        }
    }
}

CopyGUTContent(guiObj) {
    try {
        if (guiObj.HasProp("originalContent")) {
            A_Clipboard := guiObj.originalContent
            ToolTip("📋 Copied to clipboard!")
            SetTimer((*) => ToolTip(), -1500)
        }
    }
}

DisplayItemizedContent(guiObj, items, width, height, options) {
    lv := guiObj.Add("ListView", "x5 y32 w" . (width - 10) . " h" . height
        . " -Hdr +Grid Background252526 cD4D4D4 vItemList", ["Item", "Action"])

    guiObj.itemsData := items

    for index, item in items {
        if (Type(item) = "Map") {
            itemText := item.Has("text") ? item["text"] : ""
            actionText := item.Has("actionText") ? item["actionText"] : ""
            lv.Add(, itemText, actionText)
        } else {
            lv.Add(, String(item), "")
        }
    }

    lv.ModifyCol(1, "AutoHdr")
    lv.OnEvent("DoubleClick", (ctrl, row) => OnItemizedDoubleClick(guiObj, row))
}

OnItemizedDoubleClick(guiObj, row) {
    try {
        if (!guiObj.HasProp("itemsData")) {
            return
        }

        items := guiObj.itemsData

        if (row > 0 && row <= items.Length) {
            item := items[row]
            if (Type(item) = "Map") {
                if (item.Has("callback")) {
                    item["callback"].Call()
                } else if (item.Has("copyCommand")) {
                    A_Clipboard := item["copyCommand"]
                    ToolTip("Command copied: " . item["copyCommand"])
                    SetTimer((*) => ToolTip(), -2000)
                }
            }
        }
    }
}

DisplayTreeContent(guiObj, folderPath, width, height) {
    treeText := GenerateFolderTree(String(folderPath), "", true)
    guiObj.originalContent := treeText

    editCtrl := guiObj.Add("Edit", "x5 y32 w" . (width - 10) . " h" . height
        . " +ReadOnly -E0x200 Background252526 cD4D4D4 -Wrap +HScroll +VScroll", treeText)
    editCtrl.SetFont("s9", "Consolas")
}

GenerateFolderTree(path, indent := "", isLast := true) {
    result := ""
    SplitPath(path, &folderName)

    connector := isLast ? "└── " : "├── "
    result := indent . connector . folderName . "`n"

    childIndent := indent . (isLast ? "    " : "│   ")

    folders := []
    files := []

    try {
        Loop Files, path "\*", "DF" {
            if (A_LoopFileAttrib ~= "D") {
                folders.Push(A_LoopFilePath)
            } else {
                files.Push(A_LoopFileName)
            }
        }
    }

    for index, folderPath in folders {
        isLastChild := (index = folders.Length && files.Length = 0)
        result .= GenerateFolderTree(folderPath, childIndent, isLastChild)
    }

    for index, fileName in files {
        isLastChild := (index = files.Length)
        fileConnector := isLastChild ? "└── " : "├── "
        result .= childIndent . fileConnector . fileName . "`n"
    }

    return result
}

; =====================================================================================
; SECTION 7: STEP CANVAS - Enhanced with File-Based Loading & Arrow Navigation
; =====================================================================================

class StepCanvas {
    source := ""
    GuiObj := ""
    Steps := []
    CurrentStep := 1
    isAlwaysOnTop := true
    projectTypeName := ""

    stepTextControl := ""
    codeDisplay := ""
    directionsText := ""
    auxInputText := ""
    explanationText := ""

    __New(stepsData, projectTypeName := "Project Steps") {
        global activeStepCanvas

        ; Accept either file path (string) or pre-loaded steps array
        if (Type(stepsData) = "String") {
            ; Load from file
            this.source := stepsData
            if (!this.LoadStepsFromFile(stepsData)) {
                MsgBox("Error: Could not load steps from " . stepsData, "StepCanvas Error", 16)
                return
            }
        } else if (Type(stepsData) = "Array") {
            ; Use provided steps array
            this.Steps := stepsData
            this.source := "Provided Data"
        } else {
            MsgBox("Error: Invalid steps data type", "StepCanvas Error", 16)
            return
        }

        this.projectTypeName := projectTypeName

        if (this.Steps.Length = 0) {
            MsgBox("Error: No valid steps found", "StepCanvas Error", 16)
            return
        }

        ; Create the GUI
        this.GuiObj := Gui("+AlwaysOnTop +Resize", "📚 " . projectTypeName)
        this.GuiObj.OnEvent("Close", (*) => this.OnClose())
        this.GuiObj.BackColor := "1E1E1E"

        ; Step indicator
        this.stepTextControl := this.GuiObj.Add("Text", "x10 y10 w480 h25 c00AAFF", "Step 1 of " . this.Steps.Length)
        this.stepTextControl.SetFont("s12 bold")

        ; Navigation hint
        this.GuiObj.Add("Text", "x10 y35 w480 h15 c666666", "Use ← → arrow keys or buttons to navigate • Esc to close")

        ; Code display (command)
        this.GuiObj.Add("Text", "x10 y55 w80 h20 c888888", "Command:")
        this.codeDisplay := this.GuiObj.Add("Edit", "x10 y75 w480 h80 +ReadOnly Background252526 c00FF00 -Wrap +HScroll", "")
        this.codeDisplay.SetFont("s11", "Consolas")

        ; Copy command button
        btnCopyCmd := this.GuiObj.Add("Button", "x395 y160 w95 h25", "📋 Copy Cmd")
        btnCopyCmd.OnEvent("Click", (*) => this.CopyCurrentCommand())

        ; Info section
        this.GuiObj.Add("Text", "x10 y165 w80 h20 c888888", "Directions:")
        this.directionsText := this.GuiObj.Add("Text", "x90 y165 w300 h20 cD4D4D4", "")

        this.GuiObj.Add("Text", "x10 y190 w80 h20 c888888", "Input:")
        this.auxInputText := this.GuiObj.Add("Text", "x90 y190 w400 h20 cFFAA00", "")

        this.GuiObj.Add("Text", "x10 y215 w80 h20 c888888", "Explanation:")
        this.explanationText := this.GuiObj.Add("Edit", "x10 y235 w480 h70 +ReadOnly Background252526 cD4D4D4", "")
        this.explanationText.SetFont("s9")

        ; Bottom toolbar
        this.GuiObj.Add("Text", "x5 y310 w490 h1 Background444444")

        this.GuiObj.Add("Button", "x10 y320 w90 h30", "◀ Previous").OnEvent("Click", (*) => this.PrevStep())
        this.GuiObj.Add("Button", "x110 y320 w90 h30", "Next ▶").OnEvent("Click", (*) => this.NextStep())

        ; Step jump dropdown
        this.GuiObj.Add("Text", "x210 y325 w40 h20 cD4D4D4", "Jump:")
        stepList := []
        for idx, step in this.Steps {
            stepList.Push("Step " . idx)
        }
        this.GuiObj.Add("DropDownList", "x250 y320 w80 vStepJump Choose1", stepList).OnEvent("Change", (ctrl, *) => this.JumpToStep(ctrl))

        pinBtn := this.GuiObj.Add("Button", "x340 y320 w70 h30 vPinBtn", "📌 Pin")
        pinBtn.OnEvent("Click", (*) => this.ToggleAlwaysOnTop())

        this.GuiObj.Add("Button", "x420 y320 w70 h30", "✖ Close").OnEvent("Click", (*) => this.OnClose())

        ; Show and set up hotkeys
        this.UpdateGui()
        this.GuiObj.Show("w500 h360")

        ; Set this as the active StepCanvas
        activeStepCanvas := this

        ; Register arrow key hotkeys
        this.SetupHotkeys()
    }

    SetupHotkeys() {
        HotIfWinExist("ahk_id " . this.GuiObj.Hwnd)
        Hotkey("Left", (*) => this.PrevStep(), "On")
        Hotkey("Right", (*) => this.NextStep(), "On")
        Hotkey("Escape", (*) => this.OnClose(), "On")
    }

    DisableHotkeys() {
        try {
            HotIfWinExist("ahk_id " . this.GuiObj.Hwnd)
            Hotkey("Left", "Off")
            Hotkey("Right", "Off")
            Hotkey("Escape", "Off")
        }
    }

    OnClose() {
        global activeStepCanvas
        this.DisableHotkeys()
        activeStepCanvas := ""
        this.GuiObj.Destroy()
    }

    LoadStepsFromFile(textFile) {
        if (!FileExist(textFile)) {
            return false
        }

        try {
            fileContent := FileRead(textFile)
        } catch {
            return false
        }

        lines := StrSplit(fileContent, "`n", "`r")

        for index, lineText in lines {
            lineText := Trim(lineText)
            if (lineText = "" || SubStr(lineText, 1, 1) = ";") {
                continue
            }

            parts := StrSplit(lineText, "|")

            if (parts.Length >= 5) {
                this.Steps.Push(Map(
                    "step", Trim(parts[1]),
                    "command", Trim(parts[2]),
                    "directions", Trim(parts[3]),
                    "input", Trim(parts[4]),
                    "explanation", Trim(parts[5])
                ))
            }
        }

        return (this.Steps.Length > 0)
    }

    PrevStep() {
        if (this.CurrentStep > 1) {
            this.CurrentStep--
            this.UpdateGui()
        }
    }

    NextStep() {
        if (this.CurrentStep < this.Steps.Length) {
            this.CurrentStep++
            this.UpdateGui()
        }
    }

    JumpToStep(ctrl) {
        this.CurrentStep := ctrl.Value
        this.UpdateGui()
    }

    UpdateGui() {
        if (this.CurrentStep < 1 || this.CurrentStep > this.Steps.Length) {
            return
        }

        step := this.Steps[this.CurrentStep]

        this.stepTextControl.Text := "Step " . this.CurrentStep . " of " . this.Steps.Length

        ; Handle both old format (code) and new format (command)
        if (step.Has("command")) {
            this.codeDisplay.Value := step["command"]
        } else if (step.Has("code")) {
            this.codeDisplay.Value := step["code"]
        }

        this.directionsText.Text := step["directions"]

        if (step.Has("input")) {
            this.auxInputText.Text := step["input"]
        } else if (step.Has("auxInput")) {
            this.auxInputText.Text := step["auxInput"]
        }

        this.explanationText.Value := step["explanation"]

        ; Update dropdown selection
        try {
            this.GuiObj["StepJump"].Value := this.CurrentStep
        }
    }

    CopyCurrentCommand() {
        if (this.CurrentStep >= 1 && this.CurrentStep <= this.Steps.Length) {
            step := this.Steps[this.CurrentStep]
            cmd := step.Has("command") ? step["command"] : (step.Has("code") ? step["code"] : "")
            A_Clipboard := cmd
            ToolTip("Command copied to clipboard!")
            SetTimer((*) => ToolTip(), -2000)
        }
    }

    ToggleAlwaysOnTop() {
        if (this.isAlwaysOnTop) {
            this.GuiObj.Opt("-AlwaysOnTop")
            this.isAlwaysOnTop := false
            this.GuiObj["PinBtn"].Text := "📍 Unpin"
            ToolTip("Window unpinned")
        } else {
            this.GuiObj.Opt("+AlwaysOnTop")
            this.isAlwaysOnTop := true
            this.GuiObj["PinBtn"].Text := "📌 Pin"
            ToolTip("Window pinned")
        }
        SetTimer((*) => ToolTip(), -1500)
    }
}

; =====================================================================================
; SECTION 8: LEARNING CENTER - Browse & Launch Project Tutorials
; =====================================================================================

ShowLearningCenter() {
    global StepFilesPath

    lcGui := Gui("+AlwaysOnTop", "📚 GlobalCoder Learning Center")
    lcGui.BackColor := "1E1E1E"
    lcGui.isAlwaysOnTop := true

    ; Title
    titleText := lcGui.Add("Text", "x10 y10 w580 h30 c00AAFF Center", "🎓 Project Setup Learning Center")
    titleText.SetFont("s14 bold")

    lcGui.Add("Text", "x10 y45 w580 h20 c888888 Center", "Select a language, then choose a project type to view step-by-step instructions")

    ; Language selection
    lcGui.Add("Text", "x10 y75 w150 h20 cD4D4D4", "Select Language:")
    languages := ["JavaScript", "Python", "C# / .NET", "TypeScript"]
    langDropdown := lcGui.Add("DropDownList", "x10 y95 w200 vLanguage Choose1", languages)
    langDropdown.OnEvent("Change", (ctrl, *) => UpdateProjectTypes(lcGui, ctrl.Text))

    ; Project type selection
    lcGui.Add("Text", "x10 y130 w150 h20 cD4D4D4", "Select Project Type:")
    projectDropdown := lcGui.Add("DropDownList", "x10 y150 w350 vProjectType", [])

    ; Description area
    lcGui.Add("Text", "x10 y185 w150 h20 cD4D4D4", "Description:")
    descEdit := lcGui.Add("Edit", "x10 y205 w580 h100 +ReadOnly Background252526 cD4D4D4 vDescription", "Select a project type to see its description and steps.")

    ; Bottom toolbar
    lcGui.Add("Text", "x5 y315 w590 h1 Background444444")

    btnLaunch := lcGui.Add("Button", "x10 y325 w120 h35 Default", "🚀 Launch Tutorial")
    btnLaunch.OnEvent("Click", (*) => LaunchTutorial(lcGui))

    btnBrowseFiles := lcGui.Add("Button", "x140 y325 w120 h35", "📂 Edit Steps")
    btnBrowseFiles.OnEvent("Click", (*) => Run("explorer.exe " . StepFilesPath))

    btnReload := lcGui.Add("Button", "x270 y325 w100 h35", "🔄 Reload")
    btnReload.OnEvent("Click", (*) => (lcGui.Destroy(), ShowLearningCenter()))

    btnPin := lcGui.Add("Button", "x510 y325 w80 h35 vPinBtn", "📌 Pin")
    btnPin.OnEvent("Click", (*) => ToggleGuiAlwaysOnTop(lcGui))

    ; Initialize with first language
    UpdateProjectTypes(lcGui, "JavaScript")

    lcGui.Show("w600 h370")
}

UpdateProjectTypes(guiObj, language) {
    global StepFilesPath

    ; Map language names to file paths
    langMap := Map(
        "JavaScript", StepFilesPath "\javascript\projects.steps",
        "Python", StepFilesPath "\python\projects.steps",
        "C# / .NET", StepFilesPath "\csharp\projects.steps",
        "TypeScript", StepFilesPath "\typescript\projects.steps"
    )

    if (!langMap.Has(language)) {
        return
    }

    filePath := langMap[language]
    projectTypes := StepFileLoader.GetProjectTypeNames(filePath)

    ; Update dropdown
    projectDropdown := guiObj["ProjectType"]
    projectDropdown.Delete()

    if (projectTypes.Length > 0) {
        projectDropdown.Add(projectTypes)
        projectDropdown.Value := 1

        ; Show description for first project type
        steps := StepFileLoader.GetStepsForType(filePath, projectTypes[1])
        UpdateProjectDescription(guiObj, projectTypes[1], steps)
    } else {
        projectDropdown.Add(["No project types found"])
        projectDropdown.Value := 1
        guiObj["Description"].Value := "No step definitions found for " . language . ".`n`nYou can add step definitions by editing the .steps file in:`n" . filePath
    }

    ; Set up change handler for project type dropdown
    projectDropdown.OnEvent("Change", (ctrl, *) => OnProjectTypeChange(guiObj, language, ctrl.Text))
}

OnProjectTypeChange(guiObj, language, projectType) {
    global StepFilesPath

    langMap := Map(
        "JavaScript", StepFilesPath "\javascript\projects.steps",
        "Python", StepFilesPath "\python\projects.steps",
        "C# / .NET", StepFilesPath "\csharp\projects.steps",
        "TypeScript", StepFilesPath "\typescript\projects.steps"
    )

    if (!langMap.Has(language)) {
        return
    }

    steps := StepFileLoader.GetStepsForType(langMap[language], projectType)
    UpdateProjectDescription(guiObj, projectType, steps)
}

UpdateProjectDescription(guiObj, projectType, steps) {
    desc := "📋 " . projectType . "`n"
    desc .= "─────────────────────────────────────`n"
    desc .= "Steps: " . steps.Length . "`n`n"

    if (steps.Length > 0) {
        desc .= "Quick Overview:`n"
        for idx, step in steps {
            if (idx <= 4) {  ; Show first 4 steps
                cmd := step.Has("command") ? step["command"] : ""
                desc .= "  " . idx . ". " . SubStr(cmd, 1, 50) . (StrLen(cmd) > 50 ? "..." : "") . "`n"
            }
        }
        if (steps.Length > 4) {
            desc .= "  ... and " . (steps.Length - 4) . " more steps"
        }
    }

    guiObj["Description"].Value := desc
}

LaunchTutorial(guiObj) {
    global StepFilesPath

    language := guiObj["Language"].Text
    projectType := guiObj["ProjectType"].Text

    if (projectType = "" || projectType = "No project types found") {
        MsgBox("Please select a valid project type.", "Error", 48)
        return
    }

    langMap := Map(
        "JavaScript", StepFilesPath "\javascript\projects.steps",
        "Python", StepFilesPath "\python\projects.steps",
        "C# / .NET", StepFilesPath "\csharp\projects.steps",
        "TypeScript", StepFilesPath "\typescript\projects.steps"
    )

    steps := StepFileLoader.GetStepsForType(langMap[language], projectType)

    if (steps.Length > 0) {
        guiObj.Destroy()
        StepCanvas(steps, projectType)
    } else {
        MsgBox("No steps found for " . projectType, "Error", 48)
    }
}

ShowProjectStepsBrowser() {
    ShowLearningCenter()
}

; =====================================================================================
; SECTION 9: PROJECT MANAGEMENT SYSTEM
; =====================================================================================

class ProjectManager {
    static projectsRegistry := ""
    static recentProjects := []

    static Init() {
        global ProjectsPath
        this.projectsRegistry := ProjectsPath "\projects.ini"
        this.LoadRecentProjects()
    }

    static LoadRecentProjects() {
        this.recentProjects := []
        try {
            recentStr := IniRead(this.projectsRegistry, "RecentProjects", "List", "")
            if (recentStr != "") {
                this.recentProjects := StrSplit(recentStr, "|")
            }
        }
    }

    static SaveRecentProjects() {
        recentStr := ""
        for idx, proj in this.recentProjects {
            if (idx <= 10) {
                recentStr .= (idx > 1 ? "|" : "") . proj
            }
        }
        IniWrite(recentStr, this.projectsRegistry, "RecentProjects", "List")
    }

    static AddToRecent(projectPath) {
        newRecent := []
        for idx, proj in this.recentProjects {
            if (proj != projectPath) {
                newRecent.Push(proj)
            }
        }
        newRecent.InsertAt(1, projectPath)
        this.recentProjects := newRecent
        this.SaveRecentProjects()
    }

    static OpenWithVSCode(projectPath) {
        global VSCodePath
        this.AddToRecent(projectPath)
        Run(VSCodePath . ' "' . projectPath . '"')
    }

    static OpenWithSublime(projectPath) {
        global SublimePath
        this.AddToRecent(projectPath)
        if (FileExist(SublimePath)) {
            Run('"' . SublimePath . '" "' . projectPath . '"')
        } else {
            MsgBox("Sublime Text not found at:`n" . SublimePath, "Error", 48)
        }
    }

    static OpenInTerminal(projectPath) {
        global GitBashPath
        this.AddToRecent(projectPath)
        if (FileExist(GitBashPath)) {
            Run('"' . GitBashPath . '" --cd="' . projectPath . '"')
        } else {
            Run('cmd.exe /K cd /d "' . projectPath . '"')
        }
    }

    static OpenInExplorer(projectPath) {
        this.AddToRecent(projectPath)
        Run('explorer.exe "' . projectPath . '"')
    }
}

ProjectManager.Init()

ShowNewProjectWizard() {
    global DefaultProjectRoot

    wizardGui := Gui("+AlwaysOnTop", "🆕 Create New Project")
    wizardGui.BackColor := "1E1E1E"
    wizardGui.isAlwaysOnTop := true

    wizardGui.Add("Text", "x10 y10 w150 cD4D4D4", "Project Name:")
    wizardGui.Add("Edit", "x10 y30 w380 h25 Background252526 cD4D4D4 vProjectName", "MyProject")

    wizardGui.Add("Text", "x10 y65 w150 cD4D4D4", "Location:")
    wizardGui.Add("Edit", "x10 y85 w310 h25 Background252526 cD4D4D4 vProjectPath", DefaultProjectRoot)
    btnBrowse := wizardGui.Add("Button", "x330 y85 w60 h25", "Browse")
    btnBrowse.OnEvent("Click", (*) => BrowseProjectPath(wizardGui))

    wizardGui.Add("Text", "x10 y120 w150 cD4D4D4", "Project Type:")
    projectTypes := wizardGui.Add("DropDownList", "x10 y140 w200 vProjectType Choose1 Background252526",
        [".NET Console App", ".NET Solution + Console + Library", ".NET Web API",
         "Node.js Express", "Python Virtual Env", "Empty Folder"])

    wizardGui.Add("GroupBox", "x10 y175 w380 h100 cD4D4D4", "Options")
    wizardGui.Add("Checkbox", "x20 y195 cD4D4D4 vOpenVSCode Checked", "Open in VS Code after creation")
    wizardGui.Add("Checkbox", "x20 y220 cD4D4D4 vCopyVSCodeConfig Checked", "Copy .vscode config templates")
    wizardGui.Add("Checkbox", "x20 y245 cD4D4D4 vInitGit", "Initialize Git repository")

    wizardGui.Add("Text", "x5 y280 w390 h1 Background444444")

    btnCreate := wizardGui.Add("Button", "x10 y290 w100 h30 Default", "🚀 Create")
    btnTutorial := wizardGui.Add("Button", "x120 y290 w100 h30", "📚 Tutorial")
    btnCancel := wizardGui.Add("Button", "x230 y290 w80 h30", "Cancel")
    btnPin := wizardGui.Add("Button", "x310 y290 w80 h30 vPinBtn", "📌 Pin")

    btnCreate.OnEvent("Click", (*) => CreateProject(wizardGui))
    btnTutorial.OnEvent("Click", (*) => (wizardGui.Destroy(), ShowLearningCenter()))
    btnCancel.OnEvent("Click", (*) => wizardGui.Destroy())
    btnPin.OnEvent("Click", (*) => ToggleGuiAlwaysOnTop(wizardGui))

    wizardGui.Show("w400 h330")
}

BrowseProjectPath(guiObj) {
    selectedFolder := FileSelect("D", guiObj["ProjectPath"].Value, "Select project location")
    if (selectedFolder != "") {
        guiObj["ProjectPath"].Value := selectedFolder
    }
}

CreateProject(guiObj) {
    global TemplatesPath

    savedVals := guiObj.Submit(false)

    projectName := Trim(savedVals.ProjectName)
    projectPath := Trim(savedVals.ProjectPath)
    projectType := savedVals.ProjectType
    openVSCode := savedVals.OpenVSCode
    copyConfig := savedVals.CopyVSCodeConfig
    initGit := savedVals.InitGit

    if (projectName = "") {
        MsgBox("Please enter a project name.", "Error", 48)
        return
    }

    fullPath := projectPath . "\" . projectName

    if (DirExist(fullPath)) {
        result := MsgBox("Folder already exists. Continue anyway?", "Warning", 52)
        if (result = "No") {
            return
        }
    } else {
        DirCreate(fullPath)
    }

    GUT_Display("Creating Project", "Setting up " . projectName . "...`n`nType: " . projectType, 2000)

    switch projectType {
        case ".NET Console App":
            SetupDotNetConsole(fullPath, projectName)
        case ".NET Solution + Console + Library":
            SetupDotNetFullSolution(fullPath, projectName)
        case ".NET Web API":
            SetupDotNetWebAPI(fullPath, projectName)
        case "Node.js Express":
            SetupNodeExpress(fullPath, projectName)
        case "Python Virtual Env":
            SetupPythonVenv(fullPath, projectName)
    }

    if (copyConfig) {
        vscodeSource := TemplatesPath "\.vscode"
        vscodeDest := fullPath "\.vscode"
        if (DirExist(vscodeSource) && !DirExist(vscodeDest)) {
            DirCopy(vscodeSource, vscodeDest)
        }
    }

    if (initGit) {
        RunWait('git init', fullPath, "Hide")
    }

    ProjectManager.AddToRecent(fullPath)
    guiObj.Destroy()

    if (openVSCode) {
        ProjectManager.OpenWithVSCode(fullPath)
    }

    GUT_Display("Project Created! ✅",
        "Project: " . projectName . "`n"
        . "Location: " . fullPath . "`n`n"
        . "Type: " . projectType, 4000)

    RebuildMenu()
}

SetupDotNetConsole(path, name) {
    RunWait('dotnet new console -n "' . name . '"', path, "Hide")
}

SetupDotNetWebAPI(path, name) {
    RunWait('dotnet new webapi -n "' . name . '"', path, "Hide")
}

SetupDotNetFullSolution(path, name) {
    ; ---------------------------------------------------------------------------------
    ; Full .NET solution setup - FIXED quoting for AHK v2
    ; ---------------------------------------------------------------------------------
    consoleName := name . "_Console"
    libraryName := name . "_Library"
    slnName := name

    RunWait('dotnet new sln -n "' . slnName . '"', path, "Hide")
    RunWait('dotnet new console -n "' . consoleName . '"', path, "Hide")
    RunWait('dotnet new classlib -n "' . libraryName . '"', path, "Hide")
    RunWait('dotnet sln "' . slnName . '.sln" add **/*.csproj', path, "Hide")

    consoleProj := path . "\" . consoleName . "\" . consoleName . ".csproj"
    libraryProj := path . "\" . libraryName . "\" . libraryName . ".csproj"
    RunWait('dotnet add "' . consoleProj . '" reference "' . libraryProj . '"', path, "Hide")
}

SetupNodeExpress(path, name) {
    RunWait('npm init -y', path, "Hide")
    RunWait('npm install express', path, "Hide")

    ; Create index.js with proper content
    indexContent := "
(
// index.js - Express Server
const express = require('express');
const path = require('path');

const app = express();
const PORT = 3000;

// Serve static files from ./public
app.use(express.static(path.join(__dirname, 'public')));

// JSON parsing middleware
app.use(express.json());

// API endpoint
app.get('/api/hello', (req, res) => {
    res.json({ message: 'Hello from " . name . "!' });
});

// Start server
app.listen(PORT, () => {
    console.log(`Server running at http://localhost:${PORT}`);
});
)"
    FileAppend(indexContent, path "\index.js")

    ; Create public folder and index.html
    DirCreate(path "\public")
    htmlContent := "
(
<!DOCTYPE html>
<html>
<head>
    <meta charset=""utf-8"" />
    <title>" . name . "</title>
</head>
<body>
    <h1>Hello from " . name . "!</h1>
    <script src=""main.js""></script>
</body>
</html>
)"
    FileAppend(htmlContent, path "\public\index.html")

    ; Create main.js
    jsContent := "
(
console.log('Main JS loaded');

fetch('/api/hello')
    .then(response => response.json())
    .then(data => {
        console.log('API says:', data);
    })
    .catch(console.error);
)"
    FileAppend(jsContent, path "\public\main.js")
}

SetupPythonVenv(path, name) {
    RunWait('python -m venv venv', path, "Hide")

    mainContent := "
(
#!/usr/bin/env python3
" . Chr(34) . Chr(34) . Chr(34) . "
" . name . " - Main entry point
" . Chr(34) . Chr(34) . Chr(34) . "

def main():
    print('Hello from " . name . "!')

if __name__ == '__main__':
    main()
)"
    FileAppend(mainContent, path "\main.py")
    FileAppend("# Add your dependencies here`n", path "\requirements.txt")
}

ShowRecentProjects() {
    if (ProjectManager.recentProjects.Length = 0) {
        GUT_Display("Recent Projects", "No recent projects found.`n`nCreate a new project to get started!", 3000)
        return
    }

    items := []
    for idx, projPath in ProjectManager.recentProjects {
        SplitPath(projPath, &projName)
        items.Push(Map(
            "text", projName . " - " . projPath,
            "copyCommand", projPath,
            "actionText", "Open"
        ))
    }

    options := Map()
    options["itemized"] := true
    options["width"] := 700
    options["height"] := 400

    GUT_Display("Recent Projects (double-click to copy path)", items, -1, options)
}

ShowProjectSettings() {
    global SettingsFile, DefaultProjectRoot, VSCodePath, SublimePath, GitBashPath

    settingsGui := Gui("+AlwaysOnTop", "Project Settings")
    settingsGui.BackColor := "1E1E1E"
    settingsGui.isAlwaysOnTop := true

    settingsGui.Add("Text", "x10 y10 w150 cD4D4D4", "Default Project Root:")
    settingsGui.Add("Edit", "x10 y30 w310 h25 Background252526 cD4D4D4 vDefaultRoot", DefaultProjectRoot)
    settingsGui.Add("Button", "x330 y30 w60 h25", "Browse").OnEvent("Click", (*) => BrowseAndSet(settingsGui, "DefaultRoot"))

    settingsGui.Add("Text", "x10 y65 w150 cD4D4D4", "VS Code Command/Path:")
    settingsGui.Add("Edit", "x10 y85 w380 h25 Background252526 cD4D4D4 vVSCodePath", VSCodePath)

    settingsGui.Add("Text", "x10 y120 w150 cD4D4D4", "Sublime Text Path:")
    settingsGui.Add("Edit", "x10 y140 w310 h25 Background252526 cD4D4D4 vSublimePath", SublimePath)
    settingsGui.Add("Button", "x330 y140 w60 h25", "Browse").OnEvent("Click", (*) => BrowseFileAndSet(settingsGui, "SublimePath"))

    settingsGui.Add("Text", "x10 y175 w150 cD4D4D4", "Git Bash Path:")
    settingsGui.Add("Edit", "x10 y195 w310 h25 Background252526 cD4D4D4 vGitBashPath", GitBashPath)
    settingsGui.Add("Button", "x330 y195 w60 h25", "Browse").OnEvent("Click", (*) => BrowseFileAndSet(settingsGui, "GitBashPath"))

    settingsGui.Add("Text", "x5 y235 w390 h1 Background444444")

    settingsGui.Add("Button", "x10 y245 w80 h30", "Save").OnEvent("Click", (*) => SaveProjectSettings(settingsGui))
    settingsGui.Add("Button", "x100 y245 w80 h30", "Cancel").OnEvent("Click", (*) => settingsGui.Destroy())
    settingsGui.Add("Button", "x310 y245 w80 h30 vPinBtn", "📌 Pin").OnEvent("Click", (*) => ToggleGuiAlwaysOnTop(settingsGui))

    settingsGui.Show("w400 h285")
}

BrowseAndSet(guiObj, controlName) {
    currentVal := guiObj[controlName].Value
    selectedFolder := FileSelect("D", currentVal, "Select folder")
    if (selectedFolder != "") {
        guiObj[controlName].Value := selectedFolder
    }
}

BrowseFileAndSet(guiObj, controlName) {
    currentVal := guiObj[controlName].Value
    selectedFile := FileSelect(3, currentVal, "Select executable", "Executables (*.exe)")
    if (selectedFile != "") {
        guiObj[controlName].Value := selectedFile
    }
}

SaveProjectSettings(guiObj) {
    global SettingsFile, DefaultProjectRoot, VSCodePath, SublimePath, GitBashPath

    savedVals := guiObj.Submit(false)

    DefaultProjectRoot := savedVals.DefaultRoot
    VSCodePath := savedVals.VSCodePath
    SublimePath := savedVals.SublimePath
    GitBashPath := savedVals.GitBashPath

    IniWrite(DefaultProjectRoot, SettingsFile, "Projects", "DefaultRoot")
    IniWrite(VSCodePath, SettingsFile, "Projects", "VSCodePath")
    IniWrite(SublimePath, SettingsFile, "Projects", "SublimePath")
    IniWrite(GitBashPath, SettingsFile, "Projects", "GitBashPath")

    guiObj.Destroy()
    GUT_Display("Settings Saved", "Project settings have been updated.", 2000)
}

RunDotNetCommand(path, command) {
    ; ---------------------------------------------------------------------------------
    ; FIXED: Use Format() to avoid nested quote issues in AHK v2
    ; Single quotes for the outer AHK string, double quotes for bash arguments
    ; ---------------------------------------------------------------------------------
    global GitBashPath

    if (FileExist(GitBashPath)) {
        ; Build command using Format() to handle quote escaping properly
        bashCmd := Format('"{1}" --cd="{2}" -c "dotnet {3}; read -p Press Enter to close..."', GitBashPath, path, command)
        Run(bashCmd)
    } else {
        ; Fallback to cmd.exe
        cmd := Format('cmd.exe /K cd /d "{1}" && dotnet {2}', path, command)
        Run(cmd)
    }
}

; =====================================================================================
; SECTION 10: MAIN MENU PREPARATION
; =====================================================================================

PrepareMenu(PATH) {
    global callingWindowItem, ActionsFile

    popupMenu := Menu()

    popupMenu.Add("Add Class Note", (*) => AddClassNote())
    popupMenu.Add("Show Classes", (*) => ShowClasses())
    popupMenu.Add("Google Search", (*) => GoogleSearch())
    popupMenu.Add("Find in Files", (*) => FindInFiles())
    popupMenu.Add()

    ; Project Management submenu
    projectSubMenu := Menu()
    projectSubMenu.Add("🆕 Create New Project", (*) => ShowNewProjectWizard())
    projectSubMenu.Add("📋 Recent Projects", (*) => ShowRecentProjects())
    projectSubMenu.Add()
    projectSubMenu.Add("📚 Learning Center", (*) => ShowLearningCenter())
    projectSubMenu.Add()
    projectSubMenu.Add("⚙️ Project Settings", (*) => ShowProjectSettings())
    popupMenu.Add("🚀 Project Management", projectSubMenu)

    popupMenu.Add()

    LoopOverFolder(PATH, popupMenu)

    actionsSubMenu := BuildActionsMenu(PATH)
    if (IsObject(actionsSubMenu)) {
        popupMenu.Add()
        popupMenu.Add("📁 Actions", actionsSubMenu)
    }

    adminSubMenu := Menu()
    adminSubMenu.Add("Settings", (*) => ShowSettingsGUI())
    adminSubMenu.Add("Add Action Item", (*) => ShowAddActionGUI())
    adminSubMenu.Add()
    adminSubMenu.Add("Reload Menu", (*) => RebuildMenu())
    adminSubMenu.Add("Reload Script", (*) => Reload())
    adminSubMenu.Add()
    adminSubMenu.Add("Open Script Folder", (*) => Run("explorer.exe " . A_ScriptDir))
    adminSubMenu.Add("Open Menu Folder", (*) => Run("explorer.exe " . CustomMenuPath))
    adminSubMenu.Add()
    adminSubMenu.Add("Exit", (*) => ExitApp())

    popupMenu.Add()
    popupMenu.Add("⚙️ Admin", adminSubMenu)

    callingWindowItem := "Calling Window: "
    popupMenu.Add(callingWindowItem, (*) => FocusCallingWindow())

    return popupMenu
}

LoopOverFolder(PATH, parentMenu) {
    try {
        Loop Files, PATH "\*", "DF" {
            if (A_LoopFileAttrib ~= "D") {
                subMenu := Menu()
                LoopOverFolder(A_LoopFilePath, subMenu)

                ; Add project steps option if steps.txt exists
                if (FileExist(A_LoopFilePath "\steps.txt")) {
                    subMenu.Add()
                    subMenu.Add("📋 View Project Steps", ViewProjectSteps.Bind(A_LoopFilePath))
                }

                parentMenu.Add(A_LoopFileName, subMenu)
            } else {
                parentMenu.Add(A_LoopFileName, MenuEventHandler.Bind(A_LoopFilePath))
            }
        }
    }
}

ViewProjectSteps(folderPath, *) {
    stepsFile := folderPath "\steps.txt"
    if (FileExist(stepsFile)) {
        StepCanvas(stepsFile, "Project Steps")
    } else {
        MsgBox("Steps file not found: " . stepsFile, "Error", 16)
    }
}

BuildActionsMenu(contextPath) {
    global ActionsFile

    if (!FileExist(ActionsFile)) {
        return ""
    }

    actionsSubMenu := Menu()
    actionCount := 0

    try {
        fileContent := FileRead(ActionsFile)
    } catch {
        return ""
    }

    inActionsSection := false

    for lineText in StrSplit(fileContent, "`n", "`r") {
        lineText := Trim(lineText)

        if (lineText = "" || SubStr(lineText, 1, 1) = ";") {
            continue
        }

        if (SubStr(lineText, 1, 1) = "[") {
            inActionsSection := (lineText = "[Actions]")
            continue
        }

        if (inActionsSection && InStr(lineText, "=")) {
            parts := StrSplit(lineText, "=", , 2)
            actionName := Trim(parts[1])
            functionName := Trim(parts[2])

            actionsSubMenu.Add(actionName, (*) => ExecuteAction(functionName, contextPath))
            actionCount++
        }
    }

    if (actionCount = 0) {
        return ""
    }

    return actionsSubMenu
}

ExecuteAction(functionName, contextPath) {
    switch functionName {
        case "Action_DumpClipboard":
            Action_DumpClipboard(contextPath)
        case "Action_NewFolder":
            Action_NewFolder(contextPath)
        case "Action_NewFile":
            Action_NewFile(contextPath)
        case "Action_OpenFolder":
            Action_OpenFolder(contextPath)
        case "Action_CaptureStructure":
            Action_CaptureStructure(contextPath)
        default:
            MsgBox("Unknown action: " . functionName, "Error", 16)
    }
}

; =====================================================================================
; SECTION 11: ACTION FUNCTIONS
; =====================================================================================

Action_DumpClipboard(folderPath) {
    dumpFile := folderPath "\dump.txt"

    clipContent := A_Clipboard
    if (clipContent = "") {
        GUT_Display("Dump Clipboard", "Clipboard is empty. Nothing to dump.", 3000)
        return
    }

    timestamp := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
    activeWindow := WinGetTitle("A")

    entry := "`n`n"
        . "═══════════════════════════════════════════════════════════`n"
        . "📅 " . timestamp . " | 🪟 " . activeWindow . "`n"
        . "═══════════════════════════════════════════════════════════`n"
        . clipContent

    FileAppend(entry, dumpFile)

    GUT_Display("Dump Clipboard", "Content appended to:`n" . dumpFile . "`n`nCharacters: " . StrLen(clipContent), 3000)
}

Action_NewFolder(folderPath) {
    result := InputBox("Enter the name for the new folder:", "Create New Folder", "w300 h120")

    if (result.Result = "Cancel" || result.Value = "") {
        return
    }

    newFolderPath := folderPath "\" . result.Value

    if (DirExist(newFolderPath)) {
        GUT_Display("Folder Exists", "A folder with this name already exists:`n" . newFolderPath, 4000)
        return
    }

    DirCreate(newFolderPath)
    RebuildMenu()

    GUT_Display("Folder Created", "Successfully created:`n" . newFolderPath, 3000)
}

Action_NewFile(folderPath) {
    fileGui := Gui("+AlwaysOnTop", "Create New File")
    fileGui.BackColor := "1E1E1E"
    fileGui.targetFolder := folderPath
    fileGui.isAlwaysOnTop := true

    fileGui.Add("Text", "x10 y10 w280 cD4D4D4", "Enter filename (with extension):")
    editName := fileGui.Add("Edit", "x10 y30 w280 h25 Background252526 cD4D4D4 vFileName", "")
    editName.Focus()

    fileGui.Add("Checkbox", "x10 y65 cD4D4D4 vUseClipboard", "Paste clipboard content into file")

    fileGui.Add("Text", "x5 y95 w290 h1 Background444444")

    fileGui.Add("Button", "x10 y105 w70 h30 Default", "Create").OnEvent("Click", (*) => CreateFileFromGUI(fileGui))
    fileGui.Add("Button", "x90 y105 w70 h30", "Cancel").OnEvent("Click", (*) => fileGui.Destroy())
    fileGui.Add("Button", "x220 y105 w70 h30 vPinBtn", "📌 Pin").OnEvent("Click", (*) => ToggleGuiAlwaysOnTop(fileGui))

    fileGui.Show("w300 h145")
}

CreateFileFromGUI(guiObj) {
    savedVals := guiObj.Submit(false)
    fileName := savedVals.FileName
    useClipboard := savedVals.UseClipboard
    folderPath := guiObj.targetFolder

    if (fileName = "") {
        MsgBox("Please enter a filename.", "Error", 48)
        return
    }

    newFilePath := folderPath "\" . fileName

    if (FileExist(newFilePath)) {
        MsgBox("A file with this name already exists.", "Error", 48)
        return
    }

    content := useClipboard ? A_Clipboard : ""
    FileAppend(content, newFilePath)

    guiObj.Destroy()
    RebuildMenu()
    GUT_Display("File Created", "Successfully created:`n" . newFilePath, 3000)
}

Action_OpenFolder(folderPath) {
    Run("explorer.exe " . folderPath)
}

Action_CaptureStructure(folderPath) {
    treeText := String(folderPath) . "`n" . GenerateFolderTree(String(folderPath), "", true)

    options := Map()
    options["tree"] := true
    options["width"] := 600
    options["height"] := 500

    GUT_Display("Folder Structure", folderPath, -1, options)
}

; =====================================================================================
; SECTION 12: FILE HANDLERS
; =====================================================================================

MenuEventHandler(FilePath, *) {
    if (FilePath = "") {
        return
    }

    SplitPath(FilePath, &name, &dir, &ext, &nameNoExt)

    switch StrLower(ext) {
        case "txt":
            Handler_txt(FilePath)
        case "rtf":
            Handler_RTF(FilePath)
        case "dump":
            Handler_dump(FilePath)
        case "action":
            Handler_Action(FilePath)
        case "note":
            Handler_note(FilePath)
        case "ahk":
            Handler_Ahk(FilePath)
        case "json":
            Handler_json(FilePath)
        case "html", "htm":
            Handler_html(FilePath)
        case "exe", "bat", "cmd":
            Handler_LaunchProgram(FilePath)
        case "steps":
            Handler_steps(FilePath)
        default:
            Handler_txt(FilePath)
    }
}

Handler_steps(FilePath) {
    ; Handle .steps files - show project type selection
    projectTypes := StepFileLoader.LoadFile(FilePath)

    if (projectTypes.Count = 0) {
        GUT_Display("No Steps Found", "No valid project types found in this file.", 3000)
        return
    }

    ; If only one project type, launch it directly
    if (projectTypes.Count = 1) {
        for typeName, steps in projectTypes {
            StepCanvas(steps, typeName)
            return
        }
    }

    ; Multiple project types - show selection
    items := []
    for typeName, steps in projectTypes {
        items.Push(Map(
            "text", typeName . " (" . steps.Length . " steps)",
            "callback", (*) => StepCanvas(steps, typeName)
        ))
    }

    options := Map()
    options["itemized"] := true
    options["width"] := 500
    options["height"] := 400

    GUT_Display("Select Project Type", items, -1, options)
}

Handler_txt(PATH) {
    if (!FileExist(PATH)) {
        GUT_Display("Error", "File not found:`n" . PATH, 4000)
        return
    }

    fileContent := FileRead(PATH)

    editGui := Gui("+AlwaysOnTop -Caption +ToolWindow +Border", "Text Viewer: " . PATH)
    editGui.Opt("+E0x08000000")
    editGui.BackColor := "1E1E1E"
    editGui.filePath := PATH
    editGui.isEditMode := false
    editGui.isAlwaysOnTop := true

    editGui.OnEvent("Size", EditGuiResize)

    SplitPath(PATH, &fileName)
    editGui.Add("Text", "x0 y0 w620 h25 +0x200 Background2D2D30 c00AAFF", "  📄 " . fileName)

    editCtrl := editGui.Add("Edit", "vFileContent x5 y30 w610 h390 +ReadOnly Background252526 cD4D4D4 -E0x200 +VScroll", fileContent)

    wordCount := CountWords(fileContent)
    editGui.Add("Text", "x5 y425 w400 h20 c888888", "Words: " . wordCount . " | Chars: " . StrLen(fileContent))

    editGui.Add("Text", "x5 y448 w610 h1 Background444444")

    editGui.Add("Button", "x10 y455 w70 h30", "📋 Copy").OnEvent("Click", (*) => CopyContent(editCtrl))
    editGui.Add("Button", "x90 y455 w70 h30 vEditBtn", "✏️ Edit").OnEvent("Click", (*) => ToggleEdit(editGui, editCtrl, editGui["EditBtn"]))
    editGui.Add("Button", "x450 y455 w70 h30 vPinBtn", "📌 Pin").OnEvent("Click", (*) => ToggleGuiAlwaysOnTop(editGui))
    editGui.Add("Button", "x530 y455 w80 h30", "✖️ Close").OnEvent("Click", (*) => editGui.Destroy())

    MonitorGet(MonitorGetPrimary(), &left, &top, &right, &bottom)
    posX := right - 630
    posY := top + 10

    editGui.Show("x" . posX . " y" . posY . " w620 h495 NoActivate")
    WinSetTransparent(180, "ahk_id " . editGui.Hwnd)
}

ToggleGuiAlwaysOnTop(guiObj) {
    try {
        if (guiObj.isAlwaysOnTop) {
            guiObj.Opt("-AlwaysOnTop")
            guiObj.isAlwaysOnTop := false
            try {
                guiObj["PinBtn"].Text := "📍 Unpin"
            }
            ToolTip("Window unpinned")
        } else {
            guiObj.Opt("+AlwaysOnTop")
            guiObj.isAlwaysOnTop := true
            try {
                guiObj["PinBtn"].Text := "📌 Pin"
            }
            ToolTip("Window pinned")
        }
        SetTimer((*) => ToolTip(), -1500)
    }
}

Handler_RTF(FilePath) {
    A_Clipboard := ""
    Sleep(200)

    try {
        wordApp := ComObject("Word.Application")
        oDoc := wordApp.Documents.Open(FilePath)
        Sleep(250)
        oDoc.Range.FormattedText.Copy()
        Sleep(250)

        if (!ClipWait(2)) {
            oDoc.Close(0)
            return
        }

        oDoc.Close(0)
        Sleep(250)
        Send("^v")

    } catch as err {
        MsgBox("Error opening RTF file:`n" . err.Message, "Error", 48)
    }
}

Handler_dump(PATH) {
    fileContent := A_Clipboard

    if (fileContent = "") {
        GUT_Display("Dump", "Clipboard is empty - nothing to dump.", 3000)
        return
    }

    timestamp := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
    activeWindowTitle := WinGetTitle("A")

    newContent := "`n`n#═══════════════════════════════════════`n"
        . "# " . timestamp . " | " . activeWindowTitle . "`n"
        . "#═══════════════════════════════════════`n"
        . fileContent

    FileAppend(newContent, PATH)
    GUT_Display("Dump Updated", "Content added to:`n" . PATH, 3000)
}

Handler_Action(FilePath) {
    SplitPath(FilePath, &name, &actionDir, &ext, &nameNoExt)
    SplitPath(actionDir, , &languageFolder)

    languageFolder := StrReplace(languageFolder, "\(Action)")
    languageFolder := StrReplace(languageFolder, "\Action")

    switch nameNoExt {
        case "Dump":
            Action_DumpClipboard(languageFolder)
        case "NewFolder":
            Action_NewFolder(languageFolder)
        case "NewFile":
            Action_NewFile(languageFolder)
        case "OpenFolder":
            Action_OpenFolder(languageFolder)
        case "CaptureStructure":
            Action_CaptureStructure(languageFolder)
        default:
            MsgBox("Unknown action: " . nameNoExt, "Action Handler", 48)
    }
}

Handler_note(PATH) {
    fileContent := FileRead(PATH)
    lines := StrSplit(fileContent, "`n", "`r")

    if (lines.Length < 2) {
        MsgBox("Note file must have at least 2 lines.", "Invalid Note", 48)
        return
    }

    content := ""
    for index, lineText in lines {
        if (index > 1) {
            content .= (index > 2 ? "`n" : "") . lineText
        }
    }

    A_Clipboard := content
    Sleep(50)
    Send("^v")
}

Handler_Ahk(filepath) {
    optionsMenu := Menu()
    optionsMenu.Add("View in GUT", (*) => ViewAhkInGUT(filepath))
    optionsMenu.Add("Edit in Notepad", (*) => Run("notepad.exe " . filepath))
    optionsMenu.Add("Run Script", (*) => Run(filepath))
    optionsMenu.Add()
    optionsMenu.Add("Open Containing Folder", (*) => Run("explorer.exe /select," . filepath))
    optionsMenu.Show()
}

ViewAhkInGUT(filepath) {
    content := FileRead(filepath)
    options := Map()
    options["width"] := 700
    options["height"] := 500

    actions := []
    actions.Push(Map("text", "Edit", "callback", (*) => Run("notepad.exe " . filepath)))
    actions.Push(Map("text", "Run", "callback", (*) => Run(filepath)))
    options["actions"] := actions

    GUT_Display("AHK Script: " . filepath, content, -1, options)
}

Handler_json(filepath) {
    content := FileRead(filepath)
    options := Map()
    options["width"] := 600
    options["height"] := 500
    GUT_Display("JSON: " . filepath, content, -1, options)
}

Handler_html(filepath) {
    optionsMenu := Menu()
    optionsMenu.Add("Open in Browser", (*) => Run(filepath))
    optionsMenu.Add("View Source", (*) => Handler_txt(filepath))
    optionsMenu.Show()
}

Handler_LaunchProgram(FilePath) {
    Run(FilePath)
}

; =====================================================================================
; SECTION 13: GUI HELPER FUNCTIONS
; =====================================================================================

CopyContent(editCtrl) {
    A_Clipboard := editCtrl.Value
    ToolTip("📋 Content copied to clipboard!")
    SetTimer((*) => ToolTip(), -2000)
}

ToggleEdit(guiObj, editCtrl, btnEdit) {
    if (!guiObj.isEditMode) {
        editCtrl.Opt("-ReadOnly")
        btnEdit.Text := "💾 Save"
        ToolTip("✏️ Edit mode enabled")
        WinSetTransparent(255, "ahk_id " . guiObj.Hwnd)
        guiObj.Opt("-E0x08000000 +Caption +Resize")
        guiObj.isEditMode := true
    } else {
        editCtrl.Opt("+ReadOnly")
        btnEdit.Text := "✏️ Edit"

        if (guiObj.HasProp("filePath") && guiObj.filePath != "") {
            try {
                FileDelete(guiObj.filePath)
                FileAppend(editCtrl.Value, guiObj.filePath)
                ToolTip("💾 Changes saved")
            } catch as err {
                MsgBox("Error saving file: " . err.Message, "Save Error", 48)
            }
        } else {
            ToolTip("✏️ Edit mode disabled")
        }

        WinSetTransparent(180, "ahk_id " . guiObj.Hwnd)
        guiObj.Opt("+E0x08000000 -Caption -Resize")
        guiObj.isEditMode := false
    }

    SetTimer((*) => ToolTip(), -2000)
}

EditGuiResize(guiObj, minMax, width, height) {
    if (minMax = -1) {
        return
    }

    try {
        editCtrl := guiObj["FileContent"]
        if (editCtrl) {
            editCtrl.Move(, , width - 10, height - 105)
        }
    }
}

; =====================================================================================
; SECTION 14: SETTINGS & CONFIGURATION GUIs
; =====================================================================================

ShowSettingsGUI() {
    global SettingsFile, GUT_DefaultTimeout, GUT_DefaultTransparency, CustomMenuPath

    settingsGui := Gui("+AlwaysOnTop", "GlobalCoder Settings")
    settingsGui.BackColor := "1E1E1E"
    settingsGui.isAlwaysOnTop := true

    settingsGui.Add("GroupBox", "x10 y10 w380 h150 cD4D4D4", "GUT Display Settings")

    settingsGui.Add("Text", "x20 y35 w120 cD4D4D4", "Auto-hide timeout (ms):")
    settingsGui.Add("Edit", "x150 y32 w100 Background252526 cD4D4D4 vTimeout", GUT_DefaultTimeout)

    settingsGui.Add("Text", "x20 y65 w120 cD4D4D4", "Transparency (0-255):")
    settingsGui.Add("Edit", "x150 y62 w100 Background252526 cD4D4D4 vTransparency", GUT_DefaultTransparency)

    settingsGui.Add("Text", "x20 y95 w120 cD4D4D4", "Default Width:")
    settingsGui.Add("Edit", "x150 y92 w100 Background252526 cD4D4D4 vDefWidth",
        IniRead(SettingsFile, "GUT_Display", "DefaultWidth", 500))

    settingsGui.Add("Text", "x20 y125 w120 cD4D4D4", "Default Height:")
    settingsGui.Add("Edit", "x150 y122 w100 Background252526 cD4D4D4 vDefHeight",
        IniRead(SettingsFile, "GUT_Display", "DefaultHeight", 300))

    settingsGui.Add("GroupBox", "x10 y170 w380 h80 cD4D4D4", "Paths")
    settingsGui.Add("Text", "x20 y195 w350 c888888", "Menu Folder: " . CustomMenuPath)
    settingsGui.Add("Text", "x20 y215 w350 c888888", "Settings File: " . SettingsFile)

    settingsGui.Add("Text", "x5 y255 w390 h1 Background444444")

    settingsGui.Add("Button", "x10 y265 w70 h30", "Save").OnEvent("Click", (*) => SaveSettings(settingsGui))
    settingsGui.Add("Button", "x90 y265 w70 h30", "Cancel").OnEvent("Click", (*) => settingsGui.Destroy())
    settingsGui.Add("Button", "x170 y265 w90 h30", "Open Folder").OnEvent("Click", (*) => Run("explorer.exe " . CustomMenuPath))
    settingsGui.Add("Button", "x320 y265 w70 h30 vPinBtn", "📌 Pin").OnEvent("Click", (*) => ToggleGuiAlwaysOnTop(settingsGui))

    settingsGui.Show("w400 h305")
}

SaveSettings(guiObj) {
    global SettingsFile, GUT_DefaultTimeout, GUT_DefaultTransparency, GUT_DefaultWidth, GUT_DefaultHeight

    savedVals := guiObj.Submit(false)

    timeout := Integer(savedVals.Timeout)
    transparency := Integer(savedVals.Transparency)
    width := Integer(savedVals.DefWidth)
    height := Integer(savedVals.DefHeight)

    transparency := Max(0, Min(255, transparency))

    IniWrite(timeout, SettingsFile, "GUT_Display", "Timeout")
    IniWrite(transparency, SettingsFile, "GUT_Display", "Transparency")
    IniWrite(width, SettingsFile, "GUT_Display", "DefaultWidth")
    IniWrite(height, SettingsFile, "GUT_Display", "DefaultHeight")

    GUT_DefaultTimeout := timeout
    GUT_DefaultTransparency := transparency
    GUT_DefaultWidth := width
    GUT_DefaultHeight := height

    guiObj.Destroy()
    GUT_Display("Settings Saved", "Your settings have been saved.", 2000)
}

ShowAddActionGUI() {
    global ActionsFile

    addGui := Gui("+AlwaysOnTop", "Add Action Item")
    addGui.BackColor := "1E1E1E"
    addGui.isAlwaysOnTop := true

    addGui.Add("Text", "x10 y10 w280 cD4D4D4", "Action Display Name:")
    addGui.Add("Edit", "x10 y30 w280 Background252526 cD4D4D4 vActionName", "")

    addGui.Add("Text", "x10 y60 w280 cD4D4D4", "Function Name:")
    addGui.Add("Edit", "x10 y80 w280 Background252526 cD4D4D4 vFuncName", "Action_")

    addGui.Add("Text", "x5 y115 w290 h1 Background444444")

    addGui.Add("Button", "x10 y125 w70 h30", "Add").OnEvent("Click", (*) => AddActionItem(addGui))
    addGui.Add("Button", "x90 y125 w70 h30", "Cancel").OnEvent("Click", (*) => addGui.Destroy())
    addGui.Add("Button", "x220 y125 w70 h30 vPinBtn", "📌 Pin").OnEvent("Click", (*) => ToggleGuiAlwaysOnTop(addGui))

    addGui.Show("w300 h165")
}

AddActionItem(guiObj) {
    global ActionsFile

    savedVals := guiObj.Submit(false)

    name := Trim(savedVals.ActionName)
    func := Trim(savedVals.FuncName)

    if (name = "" || func = "") {
        MsgBox("Please enter both a name and function.", "Error", 48)
        return
    }

    content := FileExist(ActionsFile) ? FileRead(ActionsFile) : "[Actions]`n`n[ActionDescriptions]`n"
    content := StrReplace(content, "[Actions]", "[Actions]`n" . name . "=" . func)

    try {
        FileDelete(ActionsFile)
    }
    FileAppend(content, ActionsFile)

    guiObj.Destroy()
    RebuildMenu()

    GUT_Display("Action Added", "New action '" . name . "' added.", 3000)
}

ShowMainFeaturesGUI() {
    global mainMenu

    mainGui := Gui("+AlwaysOnTop", "GlobalCoder Features")
    mainGui.BackColor := "1E1E1E"
    mainGui.isAlwaysOnTop := true

    titleText := mainGui.Add("Text", "x10 y10 w280 h30 c00AAFF Center", "🌐 GlobalCoder")
    titleText.SetFont("s14 bold")

    btnY := 50

    mainGui.Add("Button", "x10 y" . btnY . " w280 h35", "📋 Show Main Menu").OnEvent("Click", (*) => (mainGui.Destroy(), ShowMainMenu()))
    btnY += 45

    mainGui.Add("Button", "x10 y" . btnY . " w280 h35", "📚 Learning Center").OnEvent("Click", (*) => (mainGui.Destroy(), ShowLearningCenter()))
    btnY += 45

    mainGui.Add("Button", "x10 y" . btnY . " w280 h35", "🆕 Create New Project").OnEvent("Click", (*) => (mainGui.Destroy(), ShowNewProjectWizard()))
    btnY += 45

    mainGui.Add("Button", "x10 y" . btnY . " w280 h35", "🔍 Google Search").OnEvent("Click", (*) => (mainGui.Destroy(), GoogleSearch()))
    btnY += 45

    mainGui.Add("Button", "x10 y" . btnY . " w280 h35", "⚙️ Settings").OnEvent("Click", (*) => (mainGui.Destroy(), ShowSettingsGUI()))
    btnY += 55

    mainGui.Add("Text", "x5 y" . (btnY - 10) . " w290 h1 Background444444")

    mainGui.Add("Button", "x10 y" . btnY . " w130 h30", "✖ Close").OnEvent("Click", (*) => mainGui.Destroy())
    mainGui.Add("Button", "x160 y" . btnY . " w130 h30 vPinBtn", "📌 Pin").OnEvent("Click", (*) => ToggleGuiAlwaysOnTop(mainGui))

    mainGui.Show("w300 h" . (btnY + 40))
}

ShowMainMenu() {
    global mainMenu

    if (IsObject(mainMenu)) {
        mainMenu.Show()
    } else {
        mainMenu := PrepareMenu(CustomMenuPath)
        mainMenu.Show()
    }
}

; =====================================================================================
; SECTION 15: DEMO FUNCTIONS
; =====================================================================================

DemoGUTDisplay() {
    GUT_Display("Demo: GUT-Display",
        "This is the GUT-Display - a transparent, non-focusable popup.`n`n"
        . "Features:`n"
        . "• Doesn't steal focus from your work`n"
        . "• Auto-hides after timeout`n"
        . "• Customizable transparency`n"
        . "• COPY, PIN, and CLOSE buttons!", 5000)
}

DemoStepCanvas() {
    global StepFilesPath

    jsStepsFile := StepFilesPath "\javascript\projects.steps"

    if (FileExist(jsStepsFile)) {
        ; Get first project type
        projectTypes := StepFileLoader.LoadFile(jsStepsFile)
        for typeName, steps in projectTypes {
            StepCanvas(steps, typeName)
            return
        }
    } else {
        GUT_Display("Demo Not Available", "Steps file not found. Run the script once to generate files.", 4000)
    }
}

; =====================================================================================
; SECTION 16: UTILITY FUNCTIONS
; =====================================================================================

FindInFiles() {
    global CustomMenuPath

    result := InputBox("Enter search string:", "Find in Files", "w300 h120")

    if (result.Result = "Cancel" || result.Value = "") {
        return
    }

    searchStr := result.Value
    results := []

    try {
        Loop Files, CustomMenuPath "\*.*", "RF" {
            ext := StrLower(SubStr(A_LoopFileName, -3))
            if (ext = ".exe" || ext = ".dll" || ext = ".zip") {
                continue
            }

            try {
                content := FileRead(A_LoopFilePath)
                if (InStr(content, searchStr)) {
                    relPath := StrReplace(A_LoopFilePath, CustomMenuPath . "\", "")
                    results.Push(Map("text", relPath, "copyCommand", A_LoopFilePath))
                }
            }
        }
    }

    if (results.Length > 0) {
        options := Map()
        options["itemized"] := true
        options["width"] := 600
        options["height"] := 400
        GUT_Display("Search: '" . searchStr . "' (" . results.Length . " found)", results, -1, options)
    } else {
        GUT_Display("No Results", "No matches found for: " . searchStr, 3000)
    }
}

GoogleSearch() {
    result := InputBox("Enter search query:", "Google Search", "w300 h120")

    if (result.Result = "Cancel" || result.Value = "") {
        return
    }

    query := UrlEncode(result.Value)
    url := "https://www.google.com/search?q=" . query . "&as_qdr=y1"

    Run(url)
}

UrlEncode(str) {
    result := ""
    Loop Parse, str {
        charCode := Ord(A_LoopField)
        if (A_LoopField = " ") {
            result .= "+"
        } else if ((charCode >= 48 && charCode <= 57)
                || (charCode >= 65 && charCode <= 90)
                || (charCode >= 97 && charCode <= 122)
                || A_LoopField = "-" || A_LoopField = "_" || A_LoopField = "." || A_LoopField = "~") {
            result .= A_LoopField
        } else {
            result .= "%" . Format("{:02X}", charCode)
        }
    }
    return result
}

AddClassNote() {
    global ClassesPath

    result := InputBox("Enter class name:", "Add Class Note", "w250 h120")

    if (result.Result = "Cancel" || result.Value = "") {
        return
    }

    className := result.Value
    filePath := ClassesPath "\" . className . ".cs"

    template := "using System;`n`nnamespace MyNamespace`n{`n    public class " . className . "`n    {`n        public " . className . "()`n        {`n        }`n    }`n}"

    if (!DirExist(ClassesPath)) {
        DirCreate(ClassesPath)
    }

    FileAppend(template, filePath)
    Run(filePath)
    RebuildMenu()
}

ShowClasses() {
    global ClassesPath

    classList := []

    try {
        Loop Files, ClassesPath "\*.cs" {
            classList.Push(Map("text", A_LoopFileName, "copyCommand", A_LoopFilePath))
        }
    }

    if (classList.Length > 0) {
        options := Map()
        options["itemized"] := true
        options["width"] := 400
        options["height"] := 300
        GUT_Display("C# Classes", classList, -1, options)
    } else {
        GUT_Display("No Classes", "No C# class files found.", 3000)
    }
}

CountWords(text) {
    count := 0
    Loop Parse, text, " `t`n`r" {
        if (A_LoopField != "") {
            count++
        }
    }
    return count
}

RebuildMenu() {
    global mainMenu, CustomMenuPath
    mainMenu := PrepareMenu(CustomMenuPath)
    GUT_Display("Menu Rebuilt", "Menu refreshed with current folder contents.", 2000)
}

UpdateCallingWindowInfo(menuObj) {
    global callingWindowTitle, callingWindowItem
    callingWindowTitle := WinGetTitle("A")
    try {
        if (IsObject(menuObj)) {
            menuObj.Rename(callingWindowItem, "Calling Window: " . SubStr(callingWindowTitle, 1, 30))
        }
    }
}

FocusCallingWindow() {
    global callingWindowTitle
    if (callingWindowTitle != "" && WinExist(callingWindowTitle)) {
        WinActivate(callingWindowTitle)
    }
}

LogError(exception, mode) {
    global CustomMenuPath

    errorLog := CustomMenuPath "\errorlog.txt"
    timestamp := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")

    errorText := timestamp . " | Line " . exception.Line . ": " . exception.Message . "`n"
    FileAppend(errorText, errorLog)
    OutputDebug("Error: " . exception.Message)

    return true
}

; =====================================================================================
; SECTION 17: HOTKEY DEFINITIONS
; =====================================================================================

^RShift:: {
    global mainMenu, callingWindowTitle
    callingWindowTitle := WinGetTitle("A")
    UpdateCallingWindowInfo(mainMenu)
    ShowMainMenu()
}

!RShift:: {
    global mainMenu
    UpdateCallingWindowInfo(mainMenu)
    ShowMainMenu()
}

^Space:: GoogleSearch()

^!n:: ShowNewProjectWizard()

^!l:: ShowLearningCenter()

^!r::
^!RShift:: RebuildMenu()

; =====================================================================================
; END OF SCRIPT
; =====================================================================================
