#Requires AutoHotkey v2.0
#SingleInstance Force
SetWorkingDir A_ScriptDir

; ╔══════════════════════════════════════════════════════════════╗
; ║  9i Media Controls  —  Windows  (arrow-key layout)          ║
; ║                                                              ║
; ║  Press Ctrl+Alt+Shift+K to enter MEDIA MODE, then:          ║
; ║    ←  Prev    →  Next    ↑  Play/Pause    ↓  Stop           ║
; ╚══════════════════════════════════════════════════════════════╝

; ── CONFIG ──────────────────────────────────────────────────────
TIMEOUT_ENTER  := 2000
TIMEOUT_ACTION := 800

; ── APPEARANCE ──────────────────────────────────────────────────
COL_BG   := "0C0C0C"   ; gap / outer background
COL_TILE := "171717"   ; tile fill (subtly lighter)
COL_FG   := "FFB000"   ; amber — symbols
COL_DIM  := "7A5200"   ; dim amber — labels
COL_BDR  := "A06A00"   ; tile border

; ── TILE GEOMETRY ───────────────────────────────────────────────
TW  := 74    ; tile width
TH  := 72    ; tile height
GAP := 5     ; gap between / around tiles

UP_X  := GAP + TW + GAP               ; x of centre column   =  84
ROW_Y := GAP + TH + GAP               ; y of bottom row       =  82
OSD_W := GAP*4 + TW*3                 ; total width           = 242
OSD_H := GAP*3 + TH*2                 ; total height          = 159
RGT_X := UP_X + TW + GAP              ; x of right tile       = 163

; ── STATE ───────────────────────────────────────────────────────
global g_mode    := false
global g_visible := false
global g_alpha   := 0
global g_animDir := 0

; ── OSD BUILD ───────────────────────────────────────────────────
global osd := Gui("+AlwaysOnTop -Caption +ToolWindow", "9iMediaOSD")
osd.BackColor := COL_BG

; Draw one complete tile (background + borders + symbol + label)
DrawTile(x, y, symbol, label) {
    global osd, TW, TH, COL_TILE, COL_BDR, COL_FG, COL_DIM

    ; Tile fill
    osd.Add("Text", "x" x " y" y " w" TW " h" TH " Background" COL_TILE, "")

    ; Borders (drawn after fill so they sit on top)
    osd.Add("Text", "x" x        " y" y        " w"  TW    " h1 Background" COL_BDR, "")
    osd.Add("Text", "x" x        " y" (y+TH-1) " w"  TW    " h1 Background" COL_BDR, "")
    osd.Add("Text", "x" x        " y" y        " w1 h"  TH " Background"    COL_BDR, "")
    osd.Add("Text", "x" (x+TW-1) " y" y        " w1 h"  TH " Background"    COL_BDR, "")

    ; Arrow symbol — Consolas has solid Unicode arrow coverage
    osd.SetFont("s24 c" COL_FG " Bold", "Consolas")
    osd.Add("Text", "x" x " y" (y+8) " w" TW " h32 Center Background" COL_TILE, symbol)

    ; Action label
    osd.SetFont("s8 c" COL_DIM, "Consolas")
    osd.Add("Text", "x" (x+2) " y" (y+TH-19) " w" (TW-4) " h16 Center Background" COL_TILE, label)
}

DrawTile(UP_X, GAP,   "↑", "play/pause")
DrawTile(GAP,  ROW_Y, "←", "prev")
DrawTile(UP_X, ROW_Y, "↓", "stop")
DrawTile(RGT_X, ROW_Y, "→", "next")

; ── POSITION & CLIP TO INVERTED-T ───────────────────────────────
MonitorGetWorkArea(, &mL, &mT, &mR, &mB)
global g_osdX := mR - OSD_W - 24
global g_osdY := mB - OSD_H - 24

global g_region := UP_X        "-0 "
    . (UP_X+TW) "-0 "
    . (UP_X+TW) "-" ROW_Y " "
    . OSD_W     "-" ROW_Y " "
    . OSD_W     "-" OSD_H " "
    . "0-"          OSD_H " "
    . "0-"          ROW_Y " "
    . UP_X      "-" ROW_Y

; Prime window (pre-loads it into Windows memory, sets region/transparency once)
osd.Show("x" g_osdX " y" g_osdY " w" OSD_W " h" OSD_H " NoActivate")
WinSetTransparent(0, osd)
WinSetRegion(g_region, osd)
osd.Hide()

; ── ANIMATION (fade-out only) ────────────────────────────────────
SetTimer(AnimTick, 16)
AnimTick() {
    global g_alpha, g_animDir, g_visible
    if g_animDir != -1
        return
    g_alpha := Max(0, g_alpha - 40)
    WinSetTransparent(g_alpha, osd)
    if g_alpha = 0 {
        g_animDir := 0
        g_visible := false
        osd.Hide()
    }
}

; ── OSD SHOW / HIDE ─────────────────────────────────────────────
ShowOSD(timeout_ms) {
    global g_alpha, g_animDir, g_visible
    SetTimer(AutoExit, 0)
    if !g_visible {
        g_alpha := 220
        osd.Show("x" g_osdX " y" g_osdY " w" OSD_W " h" OSD_H " NoActivate")
        WinSetTransparent(220, osd)
        WinSetRegion(g_region, osd)
        g_visible := true
    }
    g_animDir := 0
    SetTimer(AutoExit, -timeout_ms)
}

HideOSD() {
    global g_animDir
    SetTimer(AutoExit, 0)
    g_animDir := -1
}

; ── MODE ────────────────────────────────────────────────────────
EnterMode() {
    global g_mode := true
    ShowOSD(TIMEOUT_ENTER)
}
ExitMode() {
    global g_mode := false
    HideOSD()
}
AutoExit() {
    global g_mode := false
    HideOSD()
}

; ── MEDIA ───────────────────────────────────────────────────────
DoMedia(action) {
    Critical "On"
    switch action {
        case "PREV": Send "{Media_Prev}"
        case "NEXT": Send "{Media_Next}"
        case "PLAY": Send "{Media_Play_Pause}"
        case "STOP": Send "{Media_Stop}"
    }
    ShowOSD(TIMEOUT_ACTION)
}

; ── HOTKEYS ─────────────────────────────────────────────────────
^!+k:: {
    Critical "On"
    if !g_mode
        EnterMode()
    else
        ExitMode()
}

#HotIf g_mode
Left::  DoMedia("PREV")
Right:: DoMedia("NEXT")
Up::    DoMedia("PLAY")
Down::  DoMedia("STOP")
Esc::   ExitMode()
#HotIf
