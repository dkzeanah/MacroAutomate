; ═══════════════════════════════════════════════════════════════════════════════
; StudyDB.ahk - Persistence for the Real-Time Study Assistant (study-only build)
; ═══════════════════════════════════════════════════════════════════════════════
; This is the storage and retrieval layer for the study subsystem described in
; fan\REALTIME_STUDY_ASSISTANT_SPEC.md. It deliberately covers ONLY the study
; half of that specification:
;
;   * ingested material (sources, searchable passages, derived concepts)
;   * a relational concept layer (how facts relate to each other)
;   * an evidence/confidence/state extension over the existing question bank
;     (qa_item, owned by SnipParse.ahk) plus a versioned answer trail
;
; It does NOT drive the mouse or keyboard, target a browser window, or enter any
; answer anywhere. Perception is limited to material the user captures or imports
; themselves; everything here turns that material into reviewable study output.
;
; All tables live in the shared tracking database (TrackDB(), from TrackingDB.ahk)
; so the study data sits alongside the question bank it extends.
; ═══════════════════════════════════════════════════════════════════════════════

global g_StudySchemaReady := false

; ─────────────────────────────────────────────────────────────────────────────
; SCHEMA
; ─────────────────────────────────────────────────────────────────────────────
Study_Schema() {
    global g_StudySchemaReady
    if g_StudySchemaReady
        return true
    db := TrackDB()
    if !db
        return false
    ; qa_item is created by SnipParse.ahk's Qa_Schema(); make sure it exists
    ; before we try to extend it, so the study build works even if no snip has
    ; been taken yet this session.
    try Qa_Schema()
    try {
        db.Exec("CREATE TABLE IF NOT EXISTS study_setting ("
              . "key TEXT PRIMARY KEY, value TEXT)")

        db.Exec("CREATE TABLE IF NOT EXISTS study_source ("
              . "id INTEGER PRIMARY KEY AUTOINCREMENT,"
              . "kind TEXT, title TEXT, path TEXT DEFAULT '',"
              . "course TEXT DEFAULT '', topic TEXT DEFAULT '',"
              . "added_ts TEXT, bytes INTEGER DEFAULT 0, pages INTEGER DEFAULT 0,"
              . "version INTEGER DEFAULT 1, excluded INTEGER DEFAULT 0)")

        db.Exec("CREATE TABLE IF NOT EXISTS study_passage ("
              . "id INTEGER PRIMARY KEY AUTOINCREMENT,"
              . "source_id INTEGER, ordinal INTEGER DEFAULT 0, page INTEGER DEFAULT 0,"
              . "heading TEXT DEFAULT '', text TEXT NOT NULL, norm TEXT DEFAULT '',"
              . "created_ts TEXT)")
        db.Exec("CREATE INDEX IF NOT EXISTS ix_passage_src ON study_passage(source_id)")

        db.Exec("CREATE TABLE IF NOT EXISTS study_concept ("
              . "id INTEGER PRIMARY KEY AUTOINCREMENT,"
              . "name TEXT NOT NULL, norm_name TEXT DEFAULT '', definition TEXT DEFAULT '',"
              . "kind TEXT DEFAULT 'concept', importance INTEGER DEFAULT 0,"
              . "source_id INTEGER DEFAULT 0, page INTEGER DEFAULT 0,"
              . "seen INTEGER DEFAULT 1, created_ts TEXT, last_ts TEXT)")
        db.Exec("CREATE UNIQUE INDEX IF NOT EXISTS ix_concept_name ON study_concept(norm_name)")

        db.Exec("CREATE TABLE IF NOT EXISTS study_concept_link ("
              . "id INTEGER PRIMARY KEY AUTOINCREMENT,"
              . "from_id INTEGER, to_id INTEGER, relation TEXT DEFAULT 'related',"
              . "weight INTEGER DEFAULT 1)")
        db.Exec("CREATE UNIQUE INDEX IF NOT EXISTS ix_clink ON study_concept_link(from_id,to_id,relation)")

        ; The versioned answer trail - records are added, never overwritten, so a
        ; wrong answer and its correction both survive (spec section 6).
        db.Exec("CREATE TABLE IF NOT EXISTS study_answer_log ("
              . "id INTEGER PRIMARY KEY AUTOINCREMENT,"
              . "qa_id INTEGER, ts TEXT, state TEXT DEFAULT 'candidate',"
              . "answer TEXT DEFAULT '', source TEXT DEFAULT '',"
              . "provider TEXT DEFAULT '', model TEXT DEFAULT '',"
              . "confidence REAL DEFAULT 0, evidence TEXT DEFAULT '',"
              . "escalation_reason TEXT DEFAULT '', cost REAL DEFAULT 0)")
        db.Exec("CREATE INDEX IF NOT EXISTS ix_alog_qa ON study_answer_log(qa_id)")
        db.AddColumnIfMissing("study_answer_log", "choices_snapshot", "TEXT DEFAULT ''")
        db.AddColumnIfMissing("study_answer_log", "question_snapshot", "TEXT DEFAULT ''")

        ; Spaced-review bookkeeping for the question bank.
        db.Exec("CREATE TABLE IF NOT EXISTS study_review ("
              . "qa_id INTEGER PRIMARY KEY, ease REAL DEFAULT 2.5,"
              . "interval_days INTEGER DEFAULT 0, reps INTEGER DEFAULT 0,"
              . "due_ts TEXT, last_ts TEXT, last_grade INTEGER DEFAULT 0)")

        ; Extend the existing question bank with evidence/verification columns.
        ; AddColumnIfMissing keeps this safe to run against an older bank.
        if db.TableExists("qa_item") {
            db.AddColumnIfMissing("qa_item", "state",         "TEXT DEFAULT 'candidate'")
            db.AddColumnIfMissing("qa_item", "confidence",    "REAL DEFAULT 0")
            db.AddColumnIfMissing("qa_item", "answer_source", "TEXT DEFAULT ''")
            db.AddColumnIfMissing("qa_item", "provider",      "TEXT DEFAULT ''")
            db.AddColumnIfMissing("qa_item", "model",         "TEXT DEFAULT ''")
            db.AddColumnIfMissing("qa_item", "evidence",      "TEXT DEFAULT ''")
            db.AddColumnIfMissing("qa_item", "verified_ts",   "TEXT DEFAULT ''")
        }
    } catch as err {
        TrackLogError("Study_Schema", err)
        return false
    }
    g_StudySchemaReady := true
    return true
}

; ─────────────────────────────────────────────────────────────────────────────
; SETTINGS
; ─────────────────────────────────────────────────────────────────────────────
Study_SetSetting(key, value) {
    if !Study_Schema()
        return
    TrackDB().Run("INSERT INTO study_setting(key,value) VALUES(?,?) "
                . "ON CONFLICT(key) DO UPDATE SET value=excluded.value", key, value)
}

Study_GetSetting(key, default := "") {
    if !Study_Schema()
        return default
    v := TrackDB().Scalar("SELECT value FROM study_setting WHERE key=?", key)
    return (v = "" && !IsNumber(v)) ? default : v
}

; ─────────────────────────────────────────────────────────────────────────────
; SOURCES + PASSAGES
; ─────────────────────────────────────────────────────────────────────────────
Study_AddSource(kind, title, path := "", course := "", topic := "", bytes := 0, pages := 0) {
    if !Study_Schema()
        return 0
    db := TrackDB()
    now := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
    ; Re-importing the same path bumps a version instead of duplicating.
    if (path != "") {
        prev := db.QueryRow("SELECT id,version FROM study_source WHERE path=?", path)
        if prev.Count {
            db.Run("UPDATE study_source SET title=?, course=?, topic=?, bytes=?, pages=?,"
                 . " version=version+1, added_ts=?, excluded=0 WHERE id=?"
                 , title, course, topic, bytes, pages, now, prev["id"])
            ; Drop old passages so the new version is clean; the answer trail and
            ; concepts keep their own source references.
            db.Run("DELETE FROM study_passage WHERE source_id=?", prev["id"])
            return prev["id"]
        }
    }
    db.Run("INSERT INTO study_source(kind,title,path,course,topic,added_ts,bytes,pages) "
         . "VALUES(?,?,?,?,?,?,?,?)", kind, title, path, course, topic, now, bytes, pages)
    return db.LastInsertId()
}

Study_AddPassage(sourceId, text, page := 0, ordinal := 0, heading := "") {
    text := Trim(text)
    if (text = "" || !Study_Schema())
        return 0
    db := TrackDB()
    db.Run("INSERT INTO study_passage(source_id,ordinal,page,heading,text,norm,created_ts) "
         . "VALUES(?,?,?,?,?,?,?)"
         , sourceId, ordinal, page, heading, text, Study_Normalize(text)
         , FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss"))
    return db.LastInsertId()
}

Study_SourceExclude(sourceId, excluded := 1) {
    if Study_Schema()
        TrackDB().Run("UPDATE study_source SET excluded=? WHERE id=?", excluded ? 1 : 0, sourceId)
}

Study_SourceDelete(sourceId) {
    if !Study_Schema()
        return
    db := TrackDB()
    db.Run("DELETE FROM study_passage WHERE source_id=?", sourceId)
    db.Run("DELETE FROM study_source WHERE id=?", sourceId)
}

Study_Sources() {
    if !Study_Schema()
        return []
    return TrackDB().Query("SELECT s.*, "
        . "(SELECT COUNT(*) FROM study_passage p WHERE p.source_id=s.id) AS passage_count "
        . "FROM study_source s ORDER BY s.id DESC")
}

Study_SourceTitle(sourceId) {
    if (!sourceId || !Study_Schema())
        return ""
    return TrackDB().Scalar("SELECT title FROM study_source WHERE id=?", sourceId)
}

; ─────────────────────────────────────────────────────────────────────────────
; CONCEPTS + RELATIONS
; ─────────────────────────────────────────────────────────────────────────────
; Upsert a concept. Re-seeing the same concept raises its importance and keeps
; the first good definition, filling a blank one if a later pass has text.
Study_AddConcept(name, definition := "", kind := "concept", sourceId := 0, page := 0, importance := 1) {
    name := Trim(name)
    if (name = "" || !Study_Schema())
        return 0
    db := TrackDB()
    norm := Study_Normalize(name)
    now := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
    prev := db.QueryRow("SELECT id,definition FROM study_concept WHERE norm_name=?", norm)
    if prev.Count {
        if (Trim(definition) != "" && Trim(prev["definition"]) = "")
            db.Run("UPDATE study_concept SET definition=? WHERE id=?", definition, prev["id"])
        db.Run("UPDATE study_concept SET importance=importance+?, seen=seen+1, last_ts=? WHERE id=?"
             , importance, now, prev["id"])
        return prev["id"]
    }
    db.Run("INSERT INTO study_concept(name,norm_name,definition,kind,importance,source_id,page,created_ts,last_ts) "
         . "VALUES(?,?,?,?,?,?,?,?,?)"
         , name, norm, definition, kind, importance, sourceId, page, now, now)
    return db.LastInsertId()
}

Study_LinkConcepts(fromId, toId, relation := "related", weight := 1) {
    if (!fromId || !toId || fromId = toId || !Study_Schema())
        return
    TrackDB().Run("INSERT INTO study_concept_link(from_id,to_id,relation,weight) VALUES(?,?,?,?) "
        . "ON CONFLICT(from_id,to_id,relation) DO UPDATE SET weight=weight+excluded.weight"
        , fromId, toId, relation, weight)
}

Study_Concepts(limit := 2000) {
    if !Study_Schema()
        return []
    return TrackDB().Query("SELECT * FROM study_concept ORDER BY importance DESC, seen DESC LIMIT ?", limit)
}

Study_ConceptCount() {
    if !Study_Schema()
        return 0
    v := TrackDB().Scalar("SELECT COUNT(*) FROM study_concept")
    return IsInteger(v) ? Integer(v) : 0
}

Study_RelatedConcepts(conceptId, limit := 8) {
    if (!conceptId || !Study_Schema())
        return []
    return TrackDB().Query("SELECT c.*, l.relation, l.weight FROM study_concept_link l "
        . "JOIN study_concept c ON c.id=l.to_id WHERE l.from_id=? "
        . "ORDER BY l.weight DESC LIMIT ?", conceptId, limit)
}

; ─────────────────────────────────────────────────────────────────────────────
; RETRIEVAL - keyword overlap over passages and concepts
; ─────────────────────────────────────────────────────────────────────────────
; winsqlite3 does not reliably ship FTS5, so retrieval is done with a cheap LIKE
; prefilter on the most selective tokens followed by token-overlap scoring in
; AHK. This keeps the dependency surface to plain SQL while still ranking by
; relevance rather than returning the first match.
Study_Normalize(text) {
    s := StrLower(text)
    s := RegExReplace(s, "[^a-z0-9\s]", " ")
    s := RegExReplace(s, "\s+", " ")
    return Trim(s)
}

; Content words from a query, stopwords and very short tokens removed.
Study_Keywords(text, maxWords := 12) {
    static stop := Map(
        "the",1,"a",1,"an",1,"of",1,"and",1,"or",1,"to",1,"in",1,"is",1,"are",1,
        "was",1,"were",1,"be",1,"been",1,"for",1,"on",1,"with",1,"as",1,"by",1,
        "at",1,"it",1,"this",1,"that",1,"these",1,"those",1,"which",1,"what",1,
        "who",1,"whom",1,"how",1,"when",1,"where",1,"why",1,"their",1,"them",1,
        "they",1,"from",1,"into",1,"than",1,"then",1,"not",1,"all",1,"any",1,
        "can",1,"will",1,"would",1,"should",1,"could",1,"may",1,"might",1,
        "following",1,"each",1,"every",1,"your",1,"you",1,"about",1,"does",1,
        "do",1,"did",1,"has",1,"have",1,"had",1,"its",1,"his",1,"her",1,"our",1)
    seen := Map(), out := []
    for , t in StrSplit(Study_Normalize(text), " ") {
        if (StrLen(t) < 3 || stop.Has(t) || seen.Has(t))
            continue
        seen[t] := 1
        out.Push(t)
        if (out.Length >= maxWords)
            break
    }
    return out
}

; Retrieve the passages and concepts most relevant to a query.
; Returns Map(passages: [rows...], concepts: [rows...]) with a "score" on each.
Study_Retrieve(query, maxPassages := 6, maxConcepts := 6) {
    StudyConsole_Log("LOOKUP", "local.search", Map("query", query, "library", "TrackSQLite study_passage/study_concept"))
    out := Map("passages", [], "concepts", [])
    if !Study_Schema()
        return out
    kw := Study_Keywords(query)
    if !kw.Length
        return out
    db := TrackDB()

    ; ── passages ──────────────────────────────────────────────────────────
    ; Prefilter: any passage from a non-excluded source whose norm contains at
    ; least one keyword. Cap the candidate set so a big library stays fast.
    whereParts := [], params := []
    for , t in kw {
        whereParts.Push("p.norm LIKE ?")
        params.Push("%" . t . "%")
    }
    sql := "SELECT p.id,p.source_id,p.page,p.heading,p.text,p.norm "
         . "FROM study_passage p JOIN study_source s ON s.id=p.source_id "
         . "WHERE s.excluded=0 AND (" . Study_Join(whereParts, " OR ") . ") LIMIT 600"
    cands := []
    try cands := db.Query(sql, params*)
    scored := []
    for , r in cands {
        sc := Study_ScoreText(r["norm"], kw)
        if (sc > 0)
            scored.Push(Map("row", r, "score", sc))
    }
    Study_SortByScore(scored)
    Loop Min(maxPassages, scored.Length) {
        r := scored[A_Index]["row"]
        r["score"] := scored[A_Index]["score"]
        out["passages"].Push(r)
    }

    ; ── concepts ──────────────────────────────────────────────────────────
    whereParts := [], params := []
    for , t in kw {
        whereParts.Push("(norm_name LIKE ? OR definition LIKE ?)")
        params.Push("%" . t . "%")
        params.Push("%" . t . "%")
    }
    sql := "SELECT id,name,definition,kind,importance,source_id,page FROM study_concept "
         . "WHERE " . Study_Join(whereParts, " OR ") . " LIMIT 400"
    cands := []
    try cands := db.Query(sql, params*)
    scored := []
    for , r in cands {
        sc := Study_ScoreText(Study_Normalize(r["name"] . " " . r["definition"]), kw)
        sc += Integer(r["importance"]) * 0.25        ; importance nudges ranking
        if (sc > 0)
            scored.Push(Map("row", r, "score", sc))
    }
    Study_SortByScore(scored)
    Loop Min(maxConcepts, scored.Length) {
        r := scored[A_Index]["row"]
        r["score"] := scored[A_Index]["score"]
        out["concepts"].Push(r)
    }
    StudyConsole_Log("LOOKUP", "local.results", out)
    return out
}

; Token-overlap score: how many query keywords appear in the normalized text,
; weighted so matching more distinct keywords beats repeating one.
Study_ScoreText(norm, keywords) {
    if (norm = "")
        return 0
    score := 0.0, hits := 0
    for , t in keywords {
        n := 0, pos := 1
        while (pos := InStr(norm, t, true, pos)) {
            n++
            pos += StrLen(t)
            if (n >= 4)
                break
        }
        if (n > 0) {
            hits++
            score += 1 + (n - 1) * 0.3
        }
    }
    ; Reward breadth of coverage: a passage touching 4 keywords is worth more
    ; than one hammering a single keyword 4 times.
    return score + hits * 0.5
}

Study_SortByScore(arr) {
    ; Simple insertion sort, descending by score. The candidate sets are small
    ; (<=600) so this is cheaper than building a comparator closure.
    Loop arr.Length {
        i := A_Index
        j := i
        while (j > 1 && arr[j]["score"] > arr[j - 1]["score"]) {
            tmp := arr[j], arr[j] := arr[j - 1], arr[j - 1] := tmp
            j--
        }
    }
}

Study_Join(arr, sep) {
    out := ""
    for i, v in arr
        out .= (i > 1 ? sep : "") . v
    return out
}

; ─────────────────────────────────────────────────────────────────────────────
; ANSWER STATE + EVIDENCE TRAIL (extends qa_item)
; ─────────────────────────────────────────────────────────────────────────────
; Answer states, in order of trust:
;   candidate        a proposed answer, not yet verified (LLM output starts here)
;   source-confirmed backed by ingested material / a prior verified pair
;   user-confirmed   the user explicitly confirmed it
;   disputed         flagged as contradicted; stays out of "learn once" reuse
;   rejected         wrong; kept only as history
;
; "Learn once": only source-confirmed and user-confirmed answers are reused
; without a new model call. Everything else is re-derived.

; Record a proposed or confirmed answer. Appends to the trail AND updates the
; qa_item snapshot. Never deletes an earlier record.
Study_RecordAnswer(qaId, answer, state := "candidate", source := "", confidence := 0
                  , evidence := "", provider := "", model := "", escalationReason := "", cost := 0) {
    if (!qaId || !Study_Schema())
        return
    db := TrackDB()
    now := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
    snapshot := db.QueryRow("SELECT question,choices FROM qa_item WHERE id=?", qaId)
    db.Run("INSERT INTO study_answer_log(qa_id,ts,state,answer,source,provider,model,"
         . "confidence,evidence,escalation_reason,cost,choices_snapshot,question_snapshot) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)"
         , qaId, now, state, answer, source, provider, model, confidence, evidence
         , escalationReason, cost, snapshot.Count ? snapshot["choices"] : "", snapshot.Count ? snapshot["question"] : "")

    ; Reflect the current best answer on the qa_item row. A confirmed answer
    ; also fills the bank's own answer field so the existing roulette sees it.
    verifiedTs := (state = "user-confirmed" || state = "source-confirmed" || state = "portal-confirmed") ? now : ""
    db.Run("UPDATE qa_item SET answer=?, state=?, confidence=?, answer_source=?, "
         . "provider=?, model=?, evidence=?, verified_ts=?, answered_ts=? WHERE id=?"
         , answer, state, confidence, source, provider, model, evidence
         , verifiedTs, now, qaId)
    LearningLab_Study(qaId, answer, state, source, evidence)
}

Study_SetState(qaId, state) {
    if (!qaId || !Study_Schema())
        return
    db := TrackDB()
    now := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
    db.Run("UPDATE qa_item SET state=?, verified_ts=? WHERE id=?"
         , state, (state ~= "confirmed") ? now : "", qaId)
    ; Append a state-change marker to the trail so the history stays complete.
    cur := db.QueryRow("SELECT answer,confidence,answer_source,provider,model,evidence FROM qa_item WHERE id=?", qaId)
    if cur.Count
        db.Run("INSERT INTO study_answer_log(qa_id,ts,state,answer,source,provider,model,confidence,evidence) "
             . "VALUES(?,?,?,?,?,?,?,?,?)"
             , qaId, now, state, cur["answer"], cur["answer_source"], cur["provider"]
             , cur["model"], cur["confidence"], cur["evidence"])
    if cur.Count
        LearningLab_Study(qaId,cur["answer"],state,cur["answer_source"],cur["evidence"])
}

Study_AnswerHistory(qaId) {
    if (!qaId || !Study_Schema())
        return []
    return TrackDB().Query("SELECT * FROM study_answer_log WHERE qa_id=? ORDER BY id DESC", qaId)
}

; A verified pair for this exact question, if one exists (the "learn once" hit).
; portal-confirmed counts as verified: the portal's own feedback is ground
; truth, captured by the live automation layer (StudyLive.ahk).
Study_VerifiedAnswer(qaId) {
    if (!qaId || !Study_Schema())
        return Map()
    return TrackDB().QueryRow("SELECT answer,confidence,evidence,answer_source,state "
        . "FROM qa_item WHERE id=? AND state IN ('user-confirmed','source-confirmed','portal-confirmed') "
        . "AND answer IS NOT NULL AND answer<>''", qaId)
}
