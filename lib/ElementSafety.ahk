; ═══════════════════════════════════════════════════════════════════════════════
; ElementSafety.ahk - Classify UI elements by how DANGEROUS they are to touch
; ═══════════════════════════════════════════════════════════════════════════════
; WHY THIS EXISTS, IN PLAIN ENGLISH
; ---------------------------------
; A learning automator wants to poke at the screen to discover what things do.
; But some controls are safe to poke and some are NOT. Clicking a tab or opening
; a menu is reversible - nothing leaves your machine. Clicking "Post", "Send",
; "Delete", "Publish" or "Buy" is VOLATILE: it fires an outward, often
; irreversible action. And some controls are not actions at all - they are input
; fields (a status box, a required "*" field) that must be FILLED before the
; volatile button next to them should ever be pressed.
;
; This module sorts every element into one of four classes so the rest of the
; engine can decide what it is allowed to do on its own:
;
;   "passive"  Safe to explore. Menus, tabs, navigation, toggles, expanders.
;              The non-destructive learner MAY click these by itself.
;   "input"    A field that expects typing (edit/text/combo, "message",
;              "search", or a required "*" field). Safe to FOCUS, but it needs
;              content before the matching volatile control is used.
;   "volatile" Performs an outward / irreversible action (post, send, submit,
;              delete, pay, publish...). The learner must NEVER auto-fire these;
;              only an explicit, human-confirmed call may.
;   "unknown"  Could not be classified. Treated as unsafe-by-default: the learner
;              leaves it alone unless told otherwise.
;
; Classification is a transparent keyword match over an element's name + role +
; description, plus two escape hatches: an inline tag in the description
; ("[safety:passive]" / "[safety:volatile]" / "[safety:input]") and a runtime
; override list. Everything is data you can inspect and extend - no black box.
; ═══════════════════════════════════════════════════════════════════════════════

; ─── The keyword vocabularies (lower-case, matched as whole-ish words) ────────
; These are deliberately editable at runtime via Safety_AddKeyword(). The default
; lists cover the common cases; tune them for the apps you actually drive.

; Words that mean "this button sends something out into the world / can't be undone".
global g_SafetyVolatileWords := [
    "post", "publish", "tweet", "send", "submit", "share", "reply", "comment"
  , "delete", "remove", "discard", "destroy", "erase", "wipe", "format"
  , "buy", "purchase", "pay", "checkout", "order", "subscribe", "donate"
  , "confirm", "apply", "accept", "agree", "install", "uninstall", "overwrite"
  , "unfollow", "block", "report", "deactivate", "close account", "sign out", "log out"
  , "upload", "import", "export", "sync", "merge", "commit", "push", "deploy" ]

; Words/roles that mean "this is somewhere you type".
global g_SafetyInputWords := [
    "edit", "text box", "textbox", "textarea", "field", "input"
  , "message", "status", "caption", "search", "search box", "query"
  , "email", "password", "username", "address", "phone", "combo box", "combobox"
  , "required", "*" ]

; Words/roles that are normally reversible and safe to explore.
global g_SafetyPassiveWords := [
    "menu", "menu item", "tab", "tab item", "link", "hyperlink", "nav", "navigation"
  , "expand", "collapse", "toggle", "filter", "sort", "view", "settings", "options"
  , "home", "back", "forward", "refresh", "zoom", "help", "about", "preview", "details"
  , "next", "previous", "page", "scroll", "list item", "tree item", "radio", "checkbox" ]

; Runtime per-name overrides win over every keyword rule. Map(name -> class).
global g_SafetyOverrides := Map()

; ═══════════════════════════════════════════════════════════════════════════════
; CLASSIFICATION
; ═══════════════════════════════════════════════════════════════════════════════

; Classify by the three text signals we have about an element.
; Returns Map("class", <one of the four>, "reason", <why>).
;
; Precedence (first match wins), chosen so the SAFE answer is the default:
;   1. an explicit override registered for this exact name
;   2. an inline "[safety:...]" tag in the description
;   3. VOLATILE keywords  (checked before input, so "submit form" is volatile)
;   4. INPUT keywords / a required "*" marker
;   5. PASSIVE keywords
;   6. otherwise UNKNOWN  (treated as unsafe)
Safety_ClassifyName(name, role := "", description := "") {
    global g_SafetyOverrides, g_SafetyVolatileWords, g_SafetyInputWords, g_SafetyPassiveWords

    ; 1. Exact-name override.
    if (name != "" && g_SafetyOverrides.Has(name))
        return Map("class", g_SafetyOverrides[name], "reason", "explicit override")

    ; 2. Inline tag in the description, e.g. a human wrote "[safety:volatile]".
    if (description != "") {
        if RegExMatch(description, "i)\[safety:(passive|input|volatile|unknown)\]", &m)
            return Map("class", StrLower(m[1]), "reason", "inline [safety:] tag")
    }

    ; Build one lower-case haystack from every signal we have.
    hay := StrLower(Trim(name . " " . role . " " . description))

    ; 3. Volatile first - an outward action label trumps everything but an override/tag.
    if (hit := Safety_FirstHit(hay, g_SafetyVolatileWords))
        return Map("class", "volatile", "reason", "matched volatile word '" . hit . "'")

    ; 4. Input fields (including the "required *" convention).
    ;    A literal "*" anywhere in the name is the classic "required field" marker.
    if (InStr(name, "*"))
        return Map("class", "input", "reason", "contains required-field marker '*'")
    if (hit := Safety_FirstHit(hay, g_SafetyInputWords))
        return Map("class", "input", "reason", "matched input word '" . hit . "'")

    ; 5. Known-reversible controls.
    if (hit := Safety_FirstHit(hay, g_SafetyPassiveWords))
        return Map("class", "passive", "reason", "matched passive word '" . hit . "'")

    ; 6. Nothing matched - stay on the safe side.
    return Map("class", "unknown", "reason", "no rule matched; unsafe by default")
}

; Convenience overload: classify a tracked element row (a Map from the `element`
; table) by pulling its name/role/description. Falls back to treating `el` as a
; plain name string when it is not a Map.
Safety_Classify(el) {
    if (el is Map) {
        name := el.Has("name")        ? el["name"]        : ""
        role := el.Has("role")        ? el["role"]        : ""
        desc := el.Has("description") ? el["description"] : ""
        return Safety_ClassifyName(name, role, desc)
    }
    return Safety_ClassifyName(el, "", "")
}

; Return the first vocabulary word that appears in `hay`, or "" if none do.
; (Substring match is intentional: "Post" inside "Post to feed" should hit.)
Safety_FirstHit(hay, words) {
    for w in words {
        if (w != "" && InStr(hay, w))
            return w
    }
    return ""
}

; ─── Quick yes/no predicates built on the classifier ─────────────────────────

; True only for elements the non-destructive learner may click on its own.
Safety_IsSafeToProbe(el) {
    return Safety_Classify(el)["class"] = "passive"
}

; True for outward/irreversible controls that must never be auto-fired.
Safety_IsVolatile(el) {
    return Safety_Classify(el)["class"] = "volatile"
}

; True for fields that expect typed input.
Safety_IsInput(el) {
    return Safety_Classify(el)["class"] = "input"
}

; ═══════════════════════════════════════════════════════════════════════════════
; GUARDED ACTIONS - the safety layer the workflow engine should go through
; ═══════════════════════════════════════════════════════════════════════════════

; Click a NAMED element, but only if the safety class allows it.
;   allowVolatile : pass true ONLY when a human has explicitly approved firing a
;                   volatile control (e.g. they clicked a "yes, post it" button).
;                   The learner itself always calls this with false.
; Returns true if the click happened, false if it was refused or the element was
; not found. Relies on Element_ClickByName from ElementAutomation.ahk.
Safety_GuardedClick(name, allowVolatile := false, button := "Left", count := 1) {
    cls := Safety_ClassifyName(name)["class"]

    switch cls {
        case "passive":
            ; Reversible - fine to click as part of exploration or a workflow.
            return Element_ClickByName(name, button, count)

        case "input":
            ; Clicking an input only FOCUSES it, which is non-destructive, so we
            ; allow it - but flag that content is expected before any volatile step.
            ShowStatus("Focusing input field '" . name . "' (needs content)", "wait")
            return Element_ClickByName(name, button, count)

        case "volatile":
            if (allowVolatile) {
                ShowStatus("Firing VOLATILE control '" . name . "' (human-approved)", "ok")
                return Element_ClickByName(name, button, count)
            }
            ; Refuse: this is the whole point of the module.
            ShowStatus("Refused auto-click of VOLATILE '" . name
                     . "' - pass allowVolatile:=true to confirm", "fail")
            return false

        default: ; "unknown"
            ShowStatus("Refused click of UNCLASSIFIED '" . name
                     . "' - classify it first (safety unknown)", "fail")
            return false
    }
}

; ═══════════════════════════════════════════════════════════════════════════════
; EXTENDING / OVERRIDING THE RULES
; ═══════════════════════════════════════════════════════════════════════════════

; Add a keyword to one of the vocabularies at runtime.
;   class : "volatile" | "input" | "passive"
Safety_AddKeyword(class, word) {
    global g_SafetyVolatileWords, g_SafetyInputWords, g_SafetyPassiveWords
    word := StrLower(Trim(word))
    if (word = "")
        return false
    switch StrLower(class) {
        case "volatile": g_SafetyVolatileWords.Push(word)
        case "input":    g_SafetyInputWords.Push(word)
        case "passive":  g_SafetyPassiveWords.Push(word)
        default:         return false
    }
    return true
}

; Pin an exact element name to a class, overriding all keyword rules for it.
; Pass class "" to clear a previous override.
Safety_SetOverride(name, class) {
    global g_SafetyOverrides
    if (class = "")
        g_SafetyOverrides.Delete(name)
    else
        g_SafetyOverrides[name] := StrLower(class)
    return true
}

; ═══════════════════════════════════════════════════════════════════════════════
; BULK VIEW - classify everything in the element registry at once
; ═══════════════════════════════════════════════════════════════════════════════
; Useful for an audit before you let the learner loose on a new app: it shows, in
; one glance, which stored elements are safe to explore and which are off-limits.
; Returns Map("passive"=>[names], "input"=>[names], "volatile"=>[names], "unknown"=>[names]).
Safety_AuditRegistry(winId := 0) {
    buckets := Map("passive", [], "input", [], "volatile", [], "unknown", [])
    els := TrackDB_Elements(winId)               ; same source ElementAutomation exports from
    for el in els {
        cls := Safety_Classify(el)["class"]
        if !buckets.Has(cls)
            buckets[cls] := []
        buckets[cls].Push(el.Has("name") ? el["name"] : "")
    }
    return buckets
}
