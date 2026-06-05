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
; GUI background doubles as tile fill — no separate fill controls needed.
; This avoids the z-order repaint issue with overlapping static controls.
COL_BG  := "131313"   ; tile background (and outer fill, clipped to T by region)
COL_FG  := "FFB000"   ; amber — symbols
COL_DIM := "7A5200"   ; dim amber — labels
COL_BDR := "A06A00"   ; tile border

; ── TILE GEOMETRY ───────────────────────────────────────────────
TW  := 74
TH  := 72
GAP := 5

UP_X  := GAP + TW + GAP          ; centre column x  =  84
ROW_Y := GAP + TH + GAP          ; bottom row y      =  82
OSD_W := GAP*4 + TW*3            ; total width       = 242
OSD_H := GAP*3 + TH*2            ; total height      = 159
RGT_X := UP_X + TW + GAP         ; right tile x      = 163

; ── STATE ───────────────────────────────────────────────────────
global g_mode    := false
global g_visible := false
global g_alpha   := 0
global g_animDir := 0

; ── OSD BUILD ───────────────────────────────────────────────────
global osd := Gui("+AlwaysOnTop -Caption +ToolWindow", "9iMediaOSD")
osd.BackColor := COL_BG

; Draw a tile: text controls first (lower z-order), borders last (always on top).
; Background on each text control matches COL_BG so there are no overlapping
; fill controls — avoids Windows static control repaint/z-order issues.
DrawTile(x, y, symbol, label) {
    global osd, TW, TH, COL_BG, COL_FG, COL_DIM, COL_BDR

    ; Symbol — added before borders so borders paint on top at edges
    osd.SetFont("s24 c" COL_FG " Bold", "Consolas")
    osd.Add("Text", "x" x " y" (y+8) " w" TW " h34 Center Background" COL_BG, symbol)

    ; Label
    osd.SetFont("s8 c" COL_DIM, "Consolas")
    osd.Add("Text", "x" x " y" (y+TH-22) " w" TW " h18 Center Background" COL_BG, label)

    ; Borders last — highest z-order, always visible over text edges
    osd.Add("Text", "x" x        " y" y        " w"  TW " h1  Background" COL_BDR, "")
    osd.Add("Text", "x" x        " y" (y+TH-1) " w"  TW " h1  Background" COL_BDR, "")
    osd.Add("Text", "x" x        " y" y        " w1 h" TH " Background"   COL_BDR, "")
    osd.Add("Text", "x" (x+TW-1) " y" y        " w1 h" TH " Background"   COL_BDR, "")
}

DrawTile(UP_X,  GAP,   "↑", "play/pause")
DrawTile(GAP,   ROW_Y, "←", "prev")
DrawTile(UP_X,  ROW_Y, "↓", "stop")
DrawTile(RGT_X, ROW_Y, "→", "next")

; ── POSITION & CLIP TO INVERTED-T ───────────────────────────────
MonitorGetWorkArea(, &mL, &mT, &mR, &mB)
global g_osdX := mR - OSD_W - 24
global g_osdY := mB - OSD_H - 24

global g_region
    := UP_X         "-0 "
    . (UP_X+TW)     "-0 "
    . (UP_X+TW)     "-" ROW_Y " "
    . OSD_W         "-" ROW_Y " "
    . OSD_W         "-" OSD_H " "
    . "0-"              OSD_H " "
    . "0-"              ROW_Y " "
    . UP_X          "-" ROW_Y

; Prime window
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
