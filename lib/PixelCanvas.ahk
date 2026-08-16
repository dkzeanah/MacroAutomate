; ═══════════════════════════════════════════════════════════════════════════════
; PixelCanvas.ahk - Software 32bpp ARGB canvas with a GDI+ PNG writer
; ═══════════════════════════════════════════════════════════════════════════════
; The tracking UI needs to render three kinds of generated image:
;   * mouse heat maps            (per-cell colour ramp)
;   * mouse movement traces      (poly-lines + markers)
;   * FindText binary images     (1 bit per pixel, blown up)
;
; Rasterising into a plain pixel buffer and handing that to GDI+ once keeps the
; DllCall surface tiny and makes every draw operation trivially predictable.
;
; Colours are 0xAARRGGBB. Alpha 0xFF is opaque.
; ═══════════════════════════════════════════════════════════════════════════════

class PixelCanvas {
    w := 0
    h := 0
    stride := 0
    buf := ""

    ; Create a canvas filled with `bg`.
    __New(width, height, bg := 0xFF000000) {
        this.w := Max(1, Integer(width))
        this.h := Max(1, Integer(height))
        this.stride := this.w * 4
        this.buf := Buffer(this.stride * this.h, 0)
        if (bg != 0)
            this.Clear(bg)
    }

    Clear(color) {
        ; Fill row 0 then block-copy it down: much faster than per-pixel NumPut.
        Loop this.w
            NumPut("UInt", color, this.buf, (A_Index - 1) * 4)
        row := this.stride
        Loop this.h - 1
            DllCall("RtlMoveMemory", "Ptr", this.buf.Ptr + A_Index * row
                , "Ptr", this.buf.Ptr, "Ptr", row)
    }

    ; Write one pixel, ignoring out-of-bounds coordinates.
    SetPixel(x, y, color) {
        x := Integer(x), y := Integer(y)
        if (x < 0 || y < 0 || x >= this.w || y >= this.h)
            return
        NumPut("UInt", color, this.buf, y * this.stride + x * 4)
    }

    GetPixel(x, y) {
        x := Integer(x), y := Integer(y)
        if (x < 0 || y < 0 || x >= this.w || y >= this.h)
            return 0
        return NumGet(this.buf, y * this.stride + x * 4, "UInt")
    }

    ; Source-over alpha blend of `color` onto the existing pixel.
    BlendPixel(x, y, color) {
        x := Integer(x), y := Integer(y)
        if (x < 0 || y < 0 || x >= this.w || y >= this.h)
            return
        a := (color >> 24) & 0xFF
        if (a = 0)
            return
        if (a = 0xFF) {
            NumPut("UInt", color, this.buf, y * this.stride + x * 4)
            return
        }
        off := y * this.stride + x * 4
        dst := NumGet(this.buf, off, "UInt")
        ia := 255 - a
        r := (((color >> 16) & 0xFF) * a + ((dst >> 16) & 0xFF) * ia) // 255
        g := (((color >> 8) & 0xFF) * a + ((dst >> 8) & 0xFF) * ia) // 255
        b := ((color & 0xFF) * a + (dst & 0xFF) * ia) // 255
        NumPut("UInt", 0xFF000000 | (r << 16) | (g << 8) | b, this.buf, off)
    }

    FillRect(x, y, w, h, color) {
        x0 := Max(0, Integer(x)), y0 := Max(0, Integer(y))
        x1 := Min(this.w, Integer(x) + Integer(w))
        y1 := Min(this.h, Integer(y) + Integer(h))
        if (x1 <= x0 || y1 <= y0)
            return
        opaque := ((color >> 24) & 0xFF) = 0xFF
        yy := y0
        while (yy < y1) {
            base := yy * this.stride
            xx := x0
            while (xx < x1) {
                if opaque
                    NumPut("UInt", color, this.buf, base + xx * 4)
                else
                    this.BlendPixel(xx, yy, color)
                xx++
            }
            yy++
        }
    }

    DrawRect(x, y, w, h, color, thickness := 1) {
        this.FillRect(x, y, w, thickness, color)
        this.FillRect(x, y + h - thickness, w, thickness, color)
        this.FillRect(x, y, thickness, h, color)
        this.FillRect(x + w - thickness, y, thickness, h, color)
    }

    ; Bresenham line with optional thickness (drawn as squares along the line).
    Line(x0, y0, x1, y1, color, thickness := 1) {
        x0 := Integer(Round(x0)), y0 := Integer(Round(y0))
        x1 := Integer(Round(x1)), y1 := Integer(Round(y1))
        dx := Abs(x1 - x0)
        dy := -Abs(y1 - y0)
        sx := (x0 < x1) ? 1 : -1
        sy := (y0 < y1) ? 1 : -1
        err := dx + dy
        half := thickness // 2
        loop {
            if (thickness <= 1)
                this.BlendPixel(x0, y0, color)
            else
                this.FillRect(x0 - half, y0 - half, thickness, thickness, color)
            if (x0 = x1 && y0 = y1)
                break
            e2 := 2 * err
            if (e2 >= dy) {
                err += dy
                x0 += sx
            }
            if (e2 <= dx) {
                err += dx
                y0 += sy
            }
        }
    }

    ; Filled circle - used for click markers and heat blobs.
    Circle(cx, cy, radius, color) {
        cx := Integer(Round(cx)), cy := Integer(Round(cy)), radius := Integer(Round(radius))
        if (radius < 1) {
            this.BlendPixel(cx, cy, color)
            return
        }
        r2 := radius * radius
        dy := -radius
        while (dy <= radius) {
            dx := -radius
            while (dx <= radius) {
                if (dx * dx + dy * dy <= r2)
                    this.BlendPixel(cx + dx, cy + dy, color)
                dx++
            }
            dy++
        }
    }

    ; Radial falloff blob, the building block of the heat map.
    Blob(cx, cy, radius, r, g, b, intensity := 1.0) {
        cx := Integer(Round(cx)), cy := Integer(Round(cy))
        radius := Integer(Round(radius))
        if (radius < 1)
            radius := 1
        dy := -radius
        while (dy <= radius) {
            dx := -radius
            while (dx <= radius) {
                dist := Sqrt(dx * dx + dy * dy)
                if (dist <= radius) {
                    fall := (1 - (dist / radius)) ** 2
                    a := Integer(TrackClamp(Round(255 * fall * intensity), 0, 255))
                    if (a > 0)
                        this.BlendPixel(cx + dx, cy + dy, (a << 24) | (r << 16) | (g << 8) | b)
                }
                dx++
            }
            dy++
        }
    }

    ; ═══════════════════════════════════════════════════════════════════════
    ; OUTPUT
    ; ═══════════════════════════════════════════════════════════════════════

    ; Save as PNG (or any format Gdip_SaveBitmapToFile accepts).
    ; Returns true on success.
    Save(path) {
        ; GdipCreateBitmapFromScan0 references (does not copy) the buffer, so it
        ; must stay alive until the save completes - `this.buf` guarantees that.
        PixelFormat32bppARGB := 0x0026200A
        rc := DllCall("gdiplus\GdipCreateBitmapFromScan0"
            , "Int", this.w, "Int", this.h, "Int", this.stride
            , "Int", PixelFormat32bppARGB, "Ptr", this.buf.Ptr
            , "Ptr*", &pBitmap := 0, "Int")
        if (rc != 0 || !pBitmap)
            return false

        dir := ""
        SplitPath(path, , &dir)
        if (dir != "" && !DirExist(dir)) {
            try DirCreate(dir)
        }
        if FileExist(path) {
            try FileDelete(path)
        }

        ok := Gdip_SaveBitmapToFile(pBitmap, path) = 0
        Gdip_DisposeImage(pBitmap)
        return ok
    }
}

; ═══════════════════════════════════════════════════════════════════════════════
; COLOUR RAMPS
; ═══════════════════════════════════════════════════════════════════════════════

; Map 0..1 onto a blue -> cyan -> green -> yellow -> red heat ramp.
; Returns a Map with r, g, b keys (0-255).
HeatRampRGB(t) {
    t := TrackClamp(t, 0, 1)
    stops := [
        [0.00, 0, 0, 160],
        [0.25, 0, 190, 220],
        [0.50, 0, 200, 60],
        [0.75, 245, 210, 0],
        [1.00, 230, 30, 20]
    ]
    Loop stops.Length - 1 {
        a := stops[A_Index]
        b := stops[A_Index + 1]
        if (t >= a[1] && t <= b[1]) {
            span := b[1] - a[1]
            f := (span = 0) ? 0 : (t - a[1]) / span
            return Map("r", Round(a[2] + (b[2] - a[2]) * f)
                     , "g", Round(a[3] + (b[3] - a[3]) * f)
                     , "b", Round(a[4] + (b[4] - a[4]) * f))
        }
    }
    last := stops[stops.Length]
    return Map("r", last[2], "g", last[3], "b", last[4])
}

; Packed 0xAARRGGBB from the heat ramp.
HeatRampColor(t, alpha := 0xFF) {
    c := HeatRampRGB(t)
    return (alpha << 24) | (c["r"] << 16) | (c["g"] << 8) | c["b"]
}
