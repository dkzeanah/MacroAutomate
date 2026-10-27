; Persist photos as Base64. Files below the session cache are disposable views.
global g_PhotoCache := "", g_PhotoCacheFiles := Map()

Photo_TempPath(ext := "png") {
    global g_PhotoCache
    if g_PhotoCache = "" {
        g_PhotoCache := A_Temp . "\FanPhotos-" . DllCall("GetCurrentProcessId", "UInt") . "-" . A_TickCount
        DirCreate(g_PhotoCache)
        OnExit(Photo_ClearCache)
    }
    return g_PhotoCache . "\" . A_TickCount . "-" . Random(1, 2147483647) . "." . ext
}

Photo_ClearCache(*) {
    global g_PhotoCache
    if g_PhotoCache != "" && DirExist(g_PhotoCache) {
        ; This exact private session directory is the only cleanup target.
        Loop Files, g_PhotoCache . "\*", "F"
            try FileDelete(A_LoopFileFullPath)
        try DirDelete(g_PhotoCache)
    }
}

Photo_DataUrl(path) {
    b64 := TrackBase64EncodeFile(path)
    if b64 = ""
        throw Error("Photo encoding failed: " . path)
    SplitPath(path,,, &ext)
    ext := StrLower(ext)
    return "data:image/" . (ext = "jpg" ? "jpeg" : ext) . ";base64," . b64
}

Photo_Store(path, label := "") {
    if RegExMatch(path, "^(photo:|snapshot:|data:image/)")
        return path
    db := TrackDB()
    if !db
        throw Error("Photo database is unavailable")
    data := Photo_DataUrl(path)
    db.Exec("CREATE TABLE IF NOT EXISTS media_image(id INTEGER PRIMARY KEY AUTOINCREMENT, label TEXT, data_url TEXT NOT NULL, created_ts TEXT)")
    db.Run("INSERT INTO media_image(label,data_url,created_ts) VALUES(?,?,?)", label, data, TrackTS())
    return "photo:" . db.LastInsertId()
}

Photo_Path(value, b64 := "", ext := "png") {
    global g_PhotoCacheFiles
    if b64 = "" && value != "" && !RegExMatch(value, "^(photo:|snapshot:|data:image/)") && FileExist(value)
        return value
    if RegExMatch(value, "^photo:(\d+)$", &m) {
        db := TrackDB()
        if !db
            return ""
        value := db.Scalar("SELECT data_url FROM media_image WHERE id=?", Integer(m[1]))
    } else if RegExMatch(value, "^snapshot:(\d+)$", &m) {
        db := TrackDB()
        if !db
            return ""
        e := db.QueryRow("SELECT b64,image_format,image_path FROM snap_entry WHERE id=?", Integer(m[1]))
        return e.Count ? Photo_Path(e["image_path"], e["b64"], e["image_format"]) : ""
    }
    if RegExMatch(value, "^data:image/([a-zA-Z0-9.+-]+);base64,(.+)$", &m) {
        ext := m[1] = "jpeg" ? "jpg" : m[1], b64 := m[2]
    }
    if b64 = "" || !RegExMatch(ext, "^(png|jpg|jpeg|bmp|gif|webp)$")
        return ""
    digest := Buffer(32), digestSize := 32
    if !DllCall("crypt32\CryptHashCertificate2", "Str", "SHA256", "UInt", 0, "Ptr", 0,
        "Ptr", StrPtr(b64), "UInt", StrLen(b64)*2, "Ptr", digest, "UInt*", &digestSize)
        return ""
    key := ""
    Loop digestSize
        key .= Format("{:02x}", NumGet(digest, A_Index-1, "UChar"))
    if g_PhotoCacheFiles.Has(key) && FileExist(g_PhotoCacheFiles[key])
        return g_PhotoCacheFiles[key]
    path := Photo_TempPath(ext)
    if !TrackBase64DecodeToFile(b64, path)
        return ""
    g_PhotoCacheFiles[key] := path
    if g_PhotoCacheFiles.Count > 30 {
        for oldKey, oldPath in g_PhotoCacheFiles {
            try FileDelete(oldPath)
            g_PhotoCacheFiles.Delete(oldKey)
            break
        }
    }
    return path
}

Photo_Export(value, suggested := "photo.png") {
    path := Photo_Path(value)
    if path = ""
        return ""
    SplitPath(path,,, &ext)
    target := FileSelect("S16", suggested, "Export image", "Images (*." . ext . ")")
    if target != "" {
        if !RegExMatch(target, "i)\." . ext . "$")
            target .= "." . ext
        FileCopy(path, target, 1)
    }
    return target
}
