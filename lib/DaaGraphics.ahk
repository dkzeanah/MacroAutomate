; Small explicit GDI+ operations missing from Fan's minimal screenshot core.
DaaGdip_CreateBitmap(w,h) {
    bitmap := 0
    if DllCall("gdiplus\GdipCreateBitmapFromScan0","Int",w,"Int",h,"Int",0,"Int",0x26200A,"Ptr",0,"Ptr*",&bitmap)
        throw Error("Could not allocate scaled desktop bitmap")
    return bitmap
}
DaaGdip_GraphicsFromImage(bitmap) {
    graphics := 0
    if DllCall("gdiplus\GdipGetImageGraphicsContext","Ptr",bitmap,"Ptr*",&graphics)
        throw Error("Could not create image drawing context")
    return graphics
}
DaaGdip_DrawImage(g,b,x,y,w,h,sx,sy,sw,sh) => DllCall("gdiplus\GdipDrawImageRectRectI","Ptr",g,"Ptr",b,
    "Int",Round(x),"Int",Round(y),"Int",Round(w),"Int",Round(h),"Int",Round(sx),"Int",Round(sy),"Int",Round(sw),"Int",Round(sh),"Int",2,"Ptr",0,"Ptr",0,"Ptr",0)
DaaGdip_DeleteGraphics(g) => DllCall("gdiplus\GdipDeleteGraphics","Ptr",g)
DaaGdip_CreatePen(color,width) {
    pen := 0
    if DllCall("gdiplus\GdipCreatePen1","UInt",color,"Float",width,"Int",2,"Ptr*",&pen)
        throw Error("Could not create trail pen")
    return pen
}
DaaGdip_DeletePen(p) => DllCall("gdiplus\GdipDeletePen","Ptr",p)
DaaGdip_DrawLine(g,p,x1,y1,x2,y2) => DllCall("gdiplus\GdipDrawLine","Ptr",g,"Ptr",p,"Float",x1,"Float",y1,"Float",x2,"Float",y2)
DaaGdip_DrawEllipse(g,p,x,y,w,h) => DllCall("gdiplus\GdipDrawEllipse","Ptr",g,"Ptr",p,"Float",x,"Float",y,"Float",w,"Float",h)
