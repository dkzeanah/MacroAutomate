; ═══════════════════════════════════════════════════════════════════════════════
; TieredAutomation.ahk - The "programmatic-expense hierarchy" decision core
; ═══════════════════════════════════════════════════════════════════════════════
; WHAT THIS IS, IN PLAIN ENGLISH
; -------------------------------
; Most automation goals can be reached more than one way. To "focus Chrome" you
; could: press the taskbar Win+number shortcut, re-activate an already-open
; window, run chrome.exe, double-click a desktop icon, or Alt+Tab until you find
; it. Each of those is a "tactic". Tactics are not equal:
;
;   * some are CHEAP and RELIABLE (a keyboard shortcut - almost free, rarely fails)
;   * some are EXPENSIVE or FRAGILE (OCR the screen, Alt+Tab trial-and-error)
;
; This module lets you register a named goal (a "capability") together with its
; list of tactics, each tagged with a COST (how programmatically expensive it is;
; 1 = cheapest/most reliable, higher = dearer/more fragile). When you ask the
; engine to achieve the goal it:
;
;   * 80% of the time EXPLOITS: it runs the best tactic it currently knows, where
;     "best" = most reliable so far, divided by its cost (so cheap+reliable wins).
;   * 20% of the time EXPLORES: it picks a tactic at random. This is the
;     "randomizer" that keeps feeding fresh evidence into the rolling score, so
;     the ranking stays honest instead of freezing on one early winner.
;   * On a FAILURE it FALLS THROUGH THE CHAIN: the tactic that just failed is set
;     aside for this run and the next-best is tried, and so on, until one works or
;     the chain is exhausted. That is the "fully redundant" behaviour.
;
; Every attempt (win or lose, and how long it took) is written to SQLite so the
; "rolling score" survives restarts. That persisted score is the learning: the
; engine literally builds its own cheat-sheet of what works best on THIS machine.
;
; HOW IT CONNECTS TO THE REST
; ---------------------------
;   * It reuses the shared helpers ShowStatus / TrackLogError / TrackTS and the
;     TrackDB() SQLite connection, exactly like ResearchPipeline.ahk does.
;   * It is a drop-in generalisation of the two-tier (visual -> relative) idea
;     already in ElementAutomation.ahk: that was a hard-coded 2-step chain; this
;     is an N-step chain whose order is LEARNED rather than fixed.
;   * A tactic's "action" is just any callable that returns a truthy value on
;     success. So a tactic can wrap FindText, OCR, Acc, Element_ClickByName, a raw
;     Send, or anything else - the engine does not care HOW a tactic works, only
;     whether it worked and what it cost.
; ═══════════════════════════════════════════════════════════════════════════════

; ─── Module-wide state ───────────────────────────────────────────────────────
; g_TieredCaps maps a capability name -> an Array of tactic definitions.
; g_TieredStats is an in-memory cache of the rolling statistics so we do not hit
; SQLite on every single ranking decision; it is kept in sync with the DB.
global g_TieredCaps  := Map()
global g_TieredStats := Map()

; The 80/20 split. 20 means "20% of runs explore at random, 80% exploit the best
; known tactic". Tunable at runtime (e.g. raise it while a new machine is still
; being learned, lower it once the scores have settled).
global g_TieredExplorePct := 20

; Bayesian smoothing constants for the reliability estimate (see Tiered_ScoreValue).
; alpha/beta start a brand-new tactic at a hopeful ~67% so it actually gets tried
; a few times before the evidence takes over.
global g_TieredAlpha := 2.0
global g_TieredBeta  := 1.0

; ═══════════════════════════════════════════════════════════════════════════════
; REGISTERING CAPABILITIES
; ═══════════════════════════════════════════════════════════════════════════════

; Define (or redefine) a capability and the tactics that can achieve it.
;
;   capability : a short name, e.g. "focus_chrome" or "click:PostButton".
;   tactics    : an Array of Maps. Each tactic Map understands these keys:
;                  "name"   (required) unique label within this capability.
;                  "action" (required) a callable; returns truthy on success.
;                           It is invoked with the shared `ctx` value IF it
;                           declares a parameter, otherwise with no arguments.
;                  "cost"   (optional, default 1) the programmatic expense tier;
;                           1 = cheapest/most reliable, bigger = dearer/fragile.
;                  "verify" (optional) a second callable that CONFIRMS the real
;                           world actually changed (e.g. the window is now active).
;                           If present, the tactic only counts as a success when
;                           BOTH action and verify return truthy.
;
; Returns the number of tactics registered.
Tiered_Define(capability, tactics) {
    global g_TieredCaps

    norm := []                                   ; the cleaned-up tactic list
    for t in tactics {
        ; A tactic is useless without a name and something to run, so skip malformed ones.
        if !(t is Map) || !t.Has("name") || !t.Has("action")
            continue
        cost := t.Has("cost") ? Float(t["cost"]) : 1.0
        if (cost <= 0)                           ; guard against divide-by-zero in scoring
            cost := 1.0
        norm.Push(Map(
            "name",   t["name"],
            "cost",   cost,
            "action", t["action"],
            "verify", t.Has("verify") ? t["verify"] : ""
        ))
        ; Seed the persisted cost so the very first ranking (before any runs) is
        ; still sensible - cheapest tactic first.
        st := Tiered_StatFor(capability, t["name"])
        st["cost"] := cost
    }
    g_TieredCaps[capability] := norm
    return norm.Length
}

; The tactic list for a capability (empty Array if the capability is unknown).
Tiered_Tactics(capability) {
    global g_TieredCaps
    return g_TieredCaps.Has(capability) ? g_TieredCaps[capability] : []
}

; ═══════════════════════════════════════════════════════════════════════════════
; RUNNING A CAPABILITY (select -> act -> verify -> fall through -> learn)
; ═══════════════════════════════════════════════════════════════════════════════

; Try to achieve `capability`, falling through the tactic chain on failure.
;   ctx : an optional value handed to each tactic (e.g. a target string or Map).
; Returns Map("ok", bool, "tactic", nameUsed, "attempts", n, "ms", lastDurationMs).
Tiered_Run(capability, ctx := "") {
    tactics := Tiered_Tactics(capability)
    if !tactics.Length {
        ShowStatus("No tactics registered for capability: " . capability, "fail")
        return Map("ok", false, "tactic", "", "attempts", 0, "ms", 0)
    }

    excluded := Map()                            ; tactics that already failed THIS run
    attempts := 0

    loop {
        ; Pick the next tactic to try (exploit the best, or explore at random).
        t := Tiered_Select(capability, excluded)
        if (t = "")                              ; nothing left to try -> chain exhausted
            break

        attempts++
        name := t["name"]
        t0   := A_TickCount                      ; start the stopwatch for this attempt
        ok   := false

        try {
            ; Run the tactic's work. Tiered_Invoke passes ctx only if the
            ; callable actually accepts an argument.
            ok := Tiered_Invoke(t["action"], ctx) ? true : false

            ; If the tactic succeeded AND has a verifier, the verifier has the
            ; final say - this is how we avoid "I pressed the key but nothing
            ; happened" false positives.
            if (ok && t["verify"] != "")
                ok := Tiered_Invoke(t["verify"], ctx) ? true : false
        } catch as err {
            ; A thrown error is just another kind of failure; log it and move on.
            TrackLogError("Tiered_Run[" . capability . "/" . name . "]", err)
            ok := false
        }

        ms := A_TickCount - t0                    ; how long this attempt took

        ; Record the outcome so the rolling score (and the persisted cheat-sheet)
        ; learns from this attempt.
        Tiered_RecordOutcome(capability, name, t["cost"], ok, ms)

        if (ok) {
            ShowStatus("[" . capability . "] ok via '" . name . "' ("
                     . ms . "ms, try " . attempts . ")", "ok")
            return Map("ok", true, "tactic", name, "attempts", attempts, "ms", ms)
        }

        ; Failed: set this tactic aside for the rest of THIS run and try the next
        ; best. (It is not banned forever - next run it is eligible again.)
        excluded[name] := true
    }

    ShowStatus("[" . capability . "] exhausted all " . attempts . " tactic(s)", "fail")
    return Map("ok", false, "tactic", "", "attempts", attempts, "ms", 0)
}

; Choose the next tactic to attempt.
;   excluded : a Map of tactic names already tried-and-failed this run.
; Returns a tactic Map, or "" when every tactic has been excluded.
Tiered_Select(capability, excluded) {
    global g_TieredExplorePct

    ; Build the list of tactics still eligible this run.
    cands := []
    for t in Tiered_Tactics(capability) {
        if !excluded.Has(t["name"])
            cands.Push(t)
    }
    if !cands.Length
        return ""
    if (cands.Length = 1)                        ; no choice to make
        return cands[1]

    ; ─── EXPLORE (the 20%) ───────────────────────────────────────────────────
    ; Roll a 1-100 die; if it lands in the explore band, pick a tactic uniformly
    ; at random. This is the "randomizer of all available choices" that keeps the
    ; rolling score fed with evidence about tactics the exploiter would ignore.
    if (Random(1, 100) <= g_TieredExplorePct)
        return cands[Random(1, cands.Length)]

    ; ─── EXPLOIT (the 80%) ───────────────────────────────────────────────────
    ; Otherwise pick the highest-scoring tactic. Score already folds in both
    ; reliability and cost, so "cheap and dependable" naturally floats to the top.
    best      := cands[1]
    bestScore := Tiered_ScoreValue(Tiered_StatFor(capability, best["name"]))
    for t in cands {
        s := Tiered_ScoreValue(Tiered_StatFor(capability, t["name"]))
        if (s > bestScore) {
            best := t
            bestScore := s
        }
    }
    return best
}

; ═══════════════════════════════════════════════════════════════════════════════
; SCORING (the rolling "how good is this tactic" number)
; ═══════════════════════════════════════════════════════════════════════════════

; Turn a tactic's accumulated stats into a single comparable number.
; Higher = the engine prefers it more.
;
;   reliability = (successes + alpha) / (attempts + alpha + beta)
;       This is a smoothed success rate. The +alpha/+beta mean a tactic with no
;       history starts optimistic (so it gets tried) instead of at 0% (ignored).
;   score       = reliability / cost
;       Dividing by cost is what makes the whole thing a "programmatic-expense
;       hierarchy": between two equally reliable tactics, the cheaper one scores
;       higher and is preferred.
Tiered_ScoreValue(st) {
    global g_TieredAlpha, g_TieredBeta
    attempts  := st.Has("attempts")  ? st["attempts"]  : 0
    successes := st.Has("successes") ? st["successes"] : 0
    cost      := st.Has("cost")      ? Float(st["cost"]) : 1.0
    if (cost <= 0)
        cost := 1.0
    reliability := (successes + g_TieredAlpha) / (attempts + g_TieredAlpha + g_TieredBeta)
    return reliability / cost
}

; ═══════════════════════════════════════════════════════════════════════════════
; STATISTICS: in-memory cache backed by SQLite
; ═══════════════════════════════════════════════════════════════════════════════

; Fetch (creating on first touch) the stats Map for one tactic. The Map keys are
; cost / attempts / successes / total_ms / last_ts. Returned by reference, so
; callers that mutate it are mutating the cache too.
Tiered_StatFor(capability, tactic) {
    global g_TieredStats
    key := capability . "`n" . tactic            ; `n cannot appear in our names, so it is a safe separator
    if g_TieredStats.Has(key)
        return g_TieredStats[key]

    ; Default (fresh) stats for a never-seen tactic.
    st := Map("cost", 1.0, "attempts", 0, "successes", 0, "total_ms", 0, "last_ts", "")

    ; Try to warm it from the persisted cheat-sheet.
    db := TrackDB()
    if (db && Tiered_EnsureTable()) {
        try {
            row := db.QueryRow(
                "SELECT cost,attempts,successes,total_ms,last_ts "
              . "FROM tiered_tactic WHERE capability=? AND tactic=?"
              , capability, tactic)
            if (IsObject(row) && row.Count) {
                st["cost"]      := Float(row["cost"])
                st["attempts"]  := Integer(row["attempts"])
                st["successes"] := Integer(row["successes"])
                st["total_ms"]  := Integer(row["total_ms"])
                st["last_ts"]   := row["last_ts"]
            }
        } catch as err {
            TrackLogError("Tiered_StatFor", err)
        }
    }

    g_TieredStats[key] := st
    return st
}

; Fold one attempt's result into the stats and persist them.
Tiered_RecordOutcome(capability, tactic, cost, ok, ms) {
    st := Tiered_StatFor(capability, tactic)
    st["cost"]      := Float(cost)
    st["attempts"]  := st["attempts"]  + 1
    st["successes"] := st["successes"] + (ok ? 1 : 0)
    st["total_ms"]  := st["total_ms"]  + ms
    st["last_ts"]   := TrackTS()
    Tiered_Persist(capability, tactic, st)
}

; Create the persistence table once per session (lazy, so the module is
; self-contained and does not have to edit TrackingDB's central schema).
Tiered_EnsureTable() {
    static made := false
    if made
        return true
    db := TrackDB()
    if !db
        return false
    try {
        db.Exec(
            "CREATE TABLE IF NOT EXISTS tiered_tactic ("
          . "  capability TEXT    NOT NULL,"
          . "  tactic     TEXT    NOT NULL,"
          . "  cost       REAL    NOT NULL DEFAULT 1,"
          . "  attempts   INTEGER NOT NULL DEFAULT 0,"
          . "  successes  INTEGER NOT NULL DEFAULT 0,"
          . "  total_ms   INTEGER NOT NULL DEFAULT 0,"
          . "  last_ts    TEXT,"
          . "  PRIMARY KEY (capability, tactic))")
        made := true
    } catch as err {
        TrackLogError("Tiered_EnsureTable", err)
        return false
    }
    return true
}

; Upsert one tactic's stats into SQLite (no-op when storage is unavailable).
Tiered_Persist(capability, tactic, st) {
    db := TrackDB()
    if (!db || !Tiered_EnsureTable())
        return
    try {
        db.Run(
            "INSERT INTO tiered_tactic(capability,tactic,cost,attempts,successes,total_ms,last_ts) "
          . "VALUES(?,?,?,?,?,?,?) "
          . "ON CONFLICT(capability,tactic) DO UPDATE SET "
          . "  cost=excluded.cost, attempts=excluded.attempts, successes=excluded.successes, "
          . "  total_ms=excluded.total_ms, last_ts=excluded.last_ts"
          , capability, tactic, st["cost"], st["attempts"], st["successes"]
          , st["total_ms"], st["last_ts"])
    } catch as err {
        TrackLogError("Tiered_Persist", err)
    }
}

; ═══════════════════════════════════════════════════════════════════════════════
; SELF-CHEATSHEET / INTROSPECTION
; ═══════════════════════════════════════════════════════════════════════════════

; A human-readable table of what the engine has learned for one capability.
; Handy to drop into a tooltip, the dashboard, or a log.
Tiered_StatsReport(capability) {
    out := "Capability: " . capability . "`n"
    out .= Format("{:-22}{:>6}{:>7}{:>6}{:>7}{:>8}{:>8}`n"
                , "tactic", "cost", "tries", "wins", "rate", "avg_ms", "score")
    for t in Tiered_Tactics(capability) {
        st  := Tiered_StatFor(capability, t["name"])
        n   := st["attempts"]
        w   := st["successes"]
        rate := n ? Round(w / n * 100) : 0
        avg  := n ? Round(st["total_ms"] / n) : 0
        sc   := Round(Tiered_ScoreValue(st), 3)
        out .= Format("{:-22}{:>6}{:>7}{:>6}{:>6}%{:>8}{:>8}`n"
                    , t["name"], Round(st["cost"], 2), n, w, rate, avg, sc)
    }
    return out
}

; Record a freshly-discovered shortcut as its own low-cost tactic. This is the
; "self-cheatsheet-learning behaviour": when you (or a learning routine) find a
; cheaper way to reach a goal, register it and it immediately competes - and,
; being cheap, usually wins once it proves reliable.
;   cost defaults to 1 (cheapest) because a "shortcut" is by definition cheap.
Tiered_LearnShortcut(capability, name, action, cost := 1, verify := "") {
    tactics := Tiered_Tactics(capability)
    ; Replace an existing tactic of the same name, otherwise append.
    replaced := false
    for i, t in tactics {
        if (t["name"] = name) {
            tactics[i] := Map("name", name, "cost", Float(cost), "action", action, "verify", verify)
            replaced := true
            break
        }
    }
    if !replaced
        tactics.Push(Map("name", name, "cost", Float(cost), "action", action, "verify", verify))
    st := Tiered_StatFor(capability, name)
    st["cost"] := Float(cost)
    ShowStatus("Learned shortcut '" . name . "' for " . capability, "ok")
    return true
}

; Reset the learned stats for one capability (or every capability when "").
; Useful after moving to a new machine where the old timings no longer hold.
Tiered_Reset(capability := "") {
    global g_TieredStats
    db := TrackDB()
    if (db && Tiered_EnsureTable()) {
        try {
            if (capability = "")
                db.Run("DELETE FROM tiered_tactic")
            else
                db.Run("DELETE FROM tiered_tactic WHERE capability=?", capability)
        } catch as err {
            TrackLogError("Tiered_Reset", err)
        }
    }
    ; Drop the matching in-memory cache entries too.
    if (capability = "") {
        g_TieredStats := Map()
    } else {
        for key in g_TieredStats.Clone() {           ; clone so we can delete while iterating
            if (InStr(key, capability . "`n") = 1)
                g_TieredStats.Delete(key)
        }
    }
}

; ═══════════════════════════════════════════════════════════════════════════════
; SMALL UTILITIES
; ═══════════════════════════════════════════════════════════════════════════════

; Call `fn`, passing `ctx` only if `fn` actually takes a parameter. This lets a
; tactic be written either as `() => ...` (ignores context) or `(ctx) => ...`
; (uses it) without the caller having to know which.
Tiered_Invoke(fn, ctx) {
    takesArg := true
    try takesArg := (fn.MaxParams >= 1) || fn.IsVariadic    ; Func/Closure/BoundFunc expose these
    return takesArg ? fn(ctx) : fn()
}

; ═══════════════════════════════════════════════════════════════════════════════
; EXAMPLE: "focus_chrome" wired as a tiered capability
; ═══════════════════════════════════════════════════════════════════════════════
; This is an opt-in demonstration (call it yourself; nothing runs it on load). It
; shows the EXACT ladder the brief describes for operating Chrome, from cheapest
; to dearest, and it is the worked example the Chrome<->AHK bridge guide refers to.
; It only ever launches/focuses YOUR browser - nothing here creates accounts or
; touches site content.
;
;   taskbarPos : if Chrome is pinned to your taskbar in slot N (1-9), pass N and
;                the cheapest tactic becomes the Win+N shortcut. 0 = unknown/skip.
;   iconText   : an optional FindText pattern string for a desktop Chrome icon,
;                enabling the "double-click the desktop icon" tactic.
Tiered_RegisterBrowserFocus(exe := "chrome.exe", taskbarPos := 0, iconText := "") {
    ; A single verifier reused by every tactic: did a Chrome window actually come
    ; to the foreground within ~2 seconds? This is what stops false successes.
    verify := (*) => WinWaitActive("ahk_exe " . exe, , 2) ? true : false

    tactics := []

    ; COST 1 - taskbar Win+number. Essentially free and extremely reliable, but
    ; only available if we know Chrome's pinned slot.
    if (taskbarPos >= 1 && taskbarPos <= 9) {
        tactics.Push(Map("name", "taskbar_winkey", "cost", 1
            , "action", ((pos) => (Send("#" . pos), true)).Bind(taskbarPos)
            , "verify", verify))
    }

    ; COST 1 - re-activate an already-open Chrome window. Also near-free when a
    ; window exists; the verifier fails fast when none does, so the chain moves on.
    tactics.Push(Map("name", "activate_existing", "cost", 1
        , "action", (*) => (WinExist("ahk_exe " . exe) ? WinActivate("ahk_exe " . exe) : 0, true)
        , "verify", verify))

    ; COST 2 - launch the executable fresh. Cheap and dependable, but spawns a new
    ; process/window which is heavier than reusing one.
    tactics.Push(Map("name", "run_exe", "cost", 2
        , "action", (*) => (Run(exe), true)
        , "verify", verify))

    ; COST 3 - locate and double-click a desktop icon by its pixel pattern. Only
    ; offered when you supply a FindText pattern for the icon.
    if (iconText != "") {
        tactics.Push(Map("name", "desktop_icon", "cost", 3
            , "action", ((pat) => Tiered_ClickFindText(pat)).Bind(iconText)
            , "verify", verify))
    }

    ; COST 4 - last resort: Alt+Tab trial-and-error. Fragile and visible, so it is
    ; the dearest rung and only reached when everything above has failed.
    tactics.Push(Map("name", "alt_tab_hunt", "cost", 4
        , "action", (*) => Tiered_AltTabHunt(exe)
        , "verify", verify))

    return Tiered_Define("focus_chrome", tactics)
}

; Helper for the desktop-icon tactic: search the whole screen for a FindText
; pattern and double-click its centre. Returns true if the pattern was found.
Tiered_ClickFindText(pat) {
    ok := FindText(&x := 0, &y := 0, 0, 0, A_ScreenWidth, A_ScreenHeight, 0.12, 0.12, pat)
    if (IsObject(ok) && ok.Length) {
        Click(ok[1].x, ok[1].y, "Left", 2)       ; 2 = double-click to open the icon
        return true
    }
    return false
}

; Helper for the last-resort tactic: cycle Alt+Tab a handful of times and stop as
; soon as a window of the target exe is in front. Deliberately bounded so it can
; never spin forever.
Tiered_AltTabHunt(exe) {
    loop 12 {
        Send("{Alt down}{Tab}{Alt up}")
        Sleep(200)
        if WinActive("ahk_exe " . exe)
            return true
    }
    return false
}
