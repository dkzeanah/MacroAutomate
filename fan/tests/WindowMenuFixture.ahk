#Requires AutoHotkey v2.0
#SingleInstance Off
commands := 0
g := Gui("+AlwaysOnTop","DAA menu regression target")
counter := g.Add("Text","w350 h50","Commands: 0")
recent := Menu(), recent.Add("Example",(*)=>RecordCommand())
fixtureMenu := Menu(), fixtureMenu.Add("Open`tCtrl+O",(*)=>RecordCommand()), fixtureMenu.Add("Recent",recent)
bar := MenuBar(), bar.Add("&File",fixtureMenu), g.MenuBar := bar
g.OnEvent("Close",(*)=>ExitApp())
g.Show("w390 h180")
RecordCommand() {
    global commands, counter
    commands += 1, counter.Text := "Commands: " . commands
}
