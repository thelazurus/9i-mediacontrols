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
TIMEOUT_ENTER  := 2000   ; ms before mode exits (no key pressed)
TIMEOUT_ACTION := 800    ; ms before mode exits after each action

; ── OSD APPEARANCE ──────────────────────────────────────────────
OSD_FONT := "Lucida Console"
COL_BG   := "0C0C0C"
COL_FG   := "FFB000"   ; amber
COL_DIM  := "7A5200"   ; dim amber for labels
COL_BDR  := "A06A00"   ; tile border amber

; ── TILE GEOMETRY ───────────────────────────────────────────────
TW  := 72    ; tile width
TH  := 70    ; tile height
GAP := 4     ; gap between/around tiles

; Derived layout values
UP_X  := GAP + TW + GAP                  ; x of up/down/right column  = 80
ROW_Y := GAP + TH + GAP                  ; y where the bottom row begins = 78
OSD_W := GAP*4 + TW*3                    ; total width  = 232
OSD_H := GAP*3 + TH*2                    ; total height = 152

; ── STATE ───────────────────────────────────────────────────────
global g_mode    := false
global g_visible := false
global g_alpha   := 0
global g_animDir := 0

; ── OSD BUILD ───────────────────────────────────────────────────
global osd := Gui("+AlwaysOnTop -Caption +ToolWindow", "9iMediaOSD")
osd.BackColor := COL_BG

; Draw one tile border (four 1px strips)
DrawTileBorder(x, y) {
    global osd, TW, TH, COL_BDR
    osd.Add("Text", "x" x        " y" y        " w" TW    " h1 Background" COL_BDR, "")
    osd.Add("Text", "x" x        " y" (y+TH-1) " w" TW    " h1 Background" COL_BDR, "")
    osd.Add("Text", "x" x        " y" y        " w1 h"    TH " Background"  COL_BDR, "")
    osd.Add("Text", "x" (x+TW-1) " y" y        " w1 h"    TH " Background"  COL_BDR, "")
}

; Place the arrow symbol and action label inside a tile
DrawTileContent(x, y, symbol, label) {
    global osd, TW, TH, OSD_FONT, COL_FG, COL_DIM
    osd.SetFont("s26 c" COL_FG " Bold", OSD_FONT)
    osd.Add("Text", "x" x " y" (y+10) " w" TW " Center BackgroundTrans", symbol)
    osd.SetFont("s9 c" COL_DIM, OSD_FONT)
    osd.Add("Text", "x" x " y" (y+TH-20) " w" TW " Center BackgroundTrans", label)
}

RGT_X := UP_X + TW + GAP   ; x of right tile = 152

DrawTileBorder(UP_X, GAP)           ; ↑  play/pause
DrawTileBorder(GAP,  ROW_Y)         ; ←  prev
DrawTileBorder(UP_X, ROW_Y)         ; ↓  stop
DrawTileBorder(RGT_X, ROW_Y)        ; →  next

DrawTileContent(UP_X, GAP,    "↑", "play/pause")
DrawTileContent(GAP,  ROW_Y,  "←", "prev")
DrawTileContent(UP_X, ROW_Y,  "↓", "stop")
DrawTileContent(RGT_X, ROW_Y, "→", "next")

; ── POSITION & SHAPE ────────────────────────────────────────────
MonitorGetWorkArea(, &mL, &mT, &mR, &mB)
global g_osdX := mR - OSD_W - 24
global g_osdY := mB - OSD_H - 24

; Clip to inverted-T polygon: up column on top, full row on bottom
global g_region := UP_X "-0 "
    . (UP_X+TW) "-0 "
    . (UP_X+TW) "-" ROW_Y " "
    . OSD_W     "-" ROW_Y " "
    . OSD_W     "-" OSD_H " "
    . "0-"          OSD_H " "
    . "0-"          ROW_Y " "
    . UP_X      "-" ROW_Y

; Prime window so first show is instant
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
