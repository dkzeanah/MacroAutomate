; Page semantics from visible accessibility/OCR evidence. Reference screenshots
; describe roles, never fixed coordinates for actions on a user's browser.
StudyPortal_Action(control) {
    name := Trim(control["name"]), kind := control["kind"]
    if kind = "radio" || kind = "checkbox"
        return "select_answer"
    if kind = "edit"
        return "enter_answer"
    if kind = "dropdown"
        return "choose_answer"
    if RegExMatch(name, "i)^question\s+\d+")
        return "open_question"
    if RegExMatch(name, "i)^start$")
        return "start_assignment"
    if RegExMatch(name, "i)^check answer$|^submit(?: answer)?$|^grade$")
        return "check_answer"
    if RegExMatch(name, "i)^next(?: question)?(?: navigation)?$|^previous(?: question)?$")
        return "navigate_question"
    if RegExMatch(name, "i)^close$|^dismiss$|close.*(?:dialog|feedback)")
        return "dismiss_feedback"
    if RegExMatch(name, "i)^save$")
        return "save_progress"
    if RegExMatch(name, "i)^clear all$")
        return "clear_answer"
    if RegExMatch(name, "i)help me solve|view an example|get more help|skill builder|skillbuilder")
        return "open_help"
    if RegExMatch(name, "i)settings|menu|collapse|question list|separator|resize")
        return "page_layout"
    return "inspect"
}

StudyPortal_Profile(ocr, controls, region) {
    text := ocr["text"], view := "generic", areas := [], features := []
    if RegExMatch(text, "i)fantastic!|try again|answer(?: is)? incorrect|well done")
        view := "answer_feedback"
    else if RegExMatch(text, "i)select the correct choice|use radical notation|question list")
        view := "question_player"
    else if RegExMatch(text, "is)current score.*attempts|questions:\s*\d+.*scored:")
        view := "assignment_overview"
    questionLeft := region["x"]
    for , line in ocr["lines"] {
        if RegExMatch(line["text"], "i)^use radical notation|^solve\b|^simplify\b|^evaluate\b|^rewrite\b") {
            questionLeft := line["x"] - 24
            break
        }
    }
    for index, control in controls {
        if control["protected"]
            continue
        action := StudyPortal_Action(control)
        features.Push(Map("id", String(index), "name", control["name"], "kind", control["kind"], "action", action,
            "enabled", control.Get("enabled", true), "bounds", [control["x"], control["y"], control["w"], control["h"]]))
    }
    if view = "assignment_overview"
        areas := ["assignment name", "due date", "current score", "attempt policy", "question/score totals", "question links", "Start", "Skill Builder", "page scroll"]
    else if view = "question_player"
        areas := ["course/account header", "assignment/question navigation", "score and points", "Save", "settings/menu", "question sidebar and scroll", "prompt and expression", "answer choices and inline inputs", "pane divider", "help tools", "Clear all", "Skill Builder", "Check answer"]
    else if view = "answer_feedback"
        areas := ["modal feedback", "correct/incorrect outcome", "Close feedback", "Next question", "background controls disabled while modal is open"]
    return Map("view", view, "areas", areas, "features", features, "questionLeft", questionLeft,
        "correct", RegExMatch(text, "i)fantastic!|well done|answer is correct|correct answer") > 0)
}

StudyPortal_AssociateFields(q) {
    for , blank in q["blanks"] {
        tag := "", best := 100000, runnerUp := 100000
        for , choice in q["choices"] {
            dy := Abs((blank["y"] + blank["h"] / 2) - (choice["y"] + choice["h"] / 2))
            if dy > Max(32, choice["h"]) || blank["x"] < choice["x"]
                continue
            if dy < best {
                runnerUp := best, best := dy, tag := choice["tag"]
            } else
                runnerUp := Min(runnerUp, dy)
        }
        blank["choiceTag"] := runnerUp - best > 4 ? tag : ""
    }
}

StudyPortal_RationalPower(ocr) {
    if !RegExMatch(ocr["text"], "i)radical notation|rewrite the expression|simplify|evaluate")
        return ""
    if RegExMatch(ocr["text"], "(?<!\d)([+-]?\d{1,9})\s*\^\s*\(?\s*(\d{1,2})\s*/\s*(\d{1,2})\s*\)?", &power)
        return power[1] . "^(" . power[2] . "/" . power[3] . ")"
    ; A fractional superscript has a smaller, raised OCR box to the right of
    ; the base. Plain flattened '1001/2' is deliberately not guessed.
    expressions := Map()
    for , base in ocr["words"] {
        if !RegExMatch(base["text"], "^[+-]?\d{1,9}$")
            continue
        for , exponent in ocr["words"] {
            if !RegExMatch(exponent["text"], "^(\d{1,2})/(\d{1,2})$", &fraction)
                continue
            if exponent["x"] < base["x"] + base["w"] - 5 || exponent["x"] > base["x"] + base["w"] + Max(25, base["h"])
                continue
            if exponent["y"] >= base["y"] || exponent["y"] + exponent["h"] > base["y"] + base["h"] * 0.9
                continue
            expressions[base["text"] . "^(" . fraction[1] . "/" . fraction[2] . ")"] := true
        }
    }
    if expressions.Count = 1
        for expression in expressions
            return expression
    return ""
}
