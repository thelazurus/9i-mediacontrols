#Requires AutoHotkey v2.0
#SingleInstance Force
SetWorkingDir A_ScriptDir

; ╔══════════════════════════════════════════════════════════════╗
; ║  9i Media Controls  —  Windows                              ║
; ║                                                              ║
; ║  Press the star key to enter MEDIA MODE, then:              ║
; ║    ←  Previous track      →  Next track                     ║
; ║    ↑  Volume up           ↓  Volume down                    ║
; ║    Space  Play / Pause    Esc  Exit mode                    ║
; ║                                                              ║
; ║  Run this script once, then press the star key and check    ║
; ║  View → Key History in the tray icon to find STAR_KEY.      ║
; ╚══════════════════════════════════════════════════════════════╝

; ── CONFIGURATION ───────────────────────────────────────────────
;  To find your star key name: right-click the AHK tray icon,
;  open "Key History", press the key, look at the VK/SC column.
;  Common values for Yoga function keys: F20, F21, F22, Browser_Favorites
STAR_KEY   := "F20"     ; <─── change this to match your star key
TIMEOUT_MS := 2500      ; ms of inactivity before mode exits
VOL_STEP   := 2         ; Volume_Up/Down presses per arrow keypress

; ── OSD APPEARANCE ──────────────────────────────────────────────
OSD_W    := 420
OSD_H    := 110
OSD_FONT := "Lucida Console"
OSD_FS   := 19          ; action label font size
OSD_FS2  := 10          ; hint bar font size
COL_BG   := "0C0C0C"   ; near-black background
COL_FG   := "FFB000"   ; amber phosphor
COL_DIM  := "7A5200"   ; dimmer amber for hints
COL_BDR  := "A06A00"   ; border colour

; ── STATE ───────────────────────────────────────────────────────
global g_mode    := false
global g_visible := false

; ── BUILD OSD ───────────────────────────────────────────────────
global osd := Gui("+AlwaysOnTop -Caption +ToolWindow", "9iMediaOSD")
osd.BackColor := COL_BG

; Top + bottom border strips
osd.Add("Text", "x0 y0 w"    OSD_W " h2 Background" COL_BDR, "")
osd.Add("Text", "x0 y" (OSD_H - 2) " w" OSD_W " h2 Background" COL_BDR, "")

; Divider above hint bar
osd.Add("Text", "x10 y" (OSD_H - 35) " w" (OSD_W - 20) " h1 Background" COL_DIM, "")

; Action label (big, centred, amber)
osd.SetFont("s" OSD_FS " c" COL_FG " Bold", OSD_FONT)
global lbl_action := osd.Add("Text", "x0 y16 w" OSD_W " h50 Center +0x200", "")

; Hint bar (small, dimmer)
osd.SetFont("s" OSD_FS2 " c" COL_DIM " Normal", OSD_FONT)
global lbl_hints := osd.Add("Text", "x0 y" (OSD_H - 28) " w" OSD_W " h22 Center +0x200", "")

; Compute position: bottom-centre of working area
MonitorGetWorkArea(, &mL, &mT, &mR, &mB)
global g_scrW  := mR - mL
global g_osdX  := mL + (g_scrW - OSD_W) // 2
global g_osdY  := mB - OSD_H - 40          ; final Y when shown
global g_slideY := g_osdY + 28             ; start Y (slides up from here)

osd.Show("x" g_osdX " y" g_osdY " w" OSD_W " h" OSD_H " Hide NoActivate")
WinSetTransparent(0, osd)

; ── ANIMATION STATE ─────────────────────────────────────────────
global g_alpha     := 0
global g_animDir   := 0     ; 1 = fade in, -1 = fade out, 0 = idle
global g_animCurY  := g_slideY

SetTimer(AnimTick, 16)

AnimTick() {
    global g_alpha, g_animDir, g_animCurY, g_visible
    if g_animDir = 0
        return

    if g_animDir = 1 {
        ; Fade + slide in
        g_alpha   := Min(220, g_alpha + 32)
        g_animCurY := Round(g_animCurY + (g_osdY - g_animCurY) * 0.35)
        WinMove(g_osdX, g_animCurY,,, osd)
        WinSetTransparent(g_alpha, osd)
        if g_alpha >= 220 {
            g_animDir := 0
            g_animCurY := g_osdY
            WinMove(g_osdX, g_osdY,,, osd)
            WinSetTransparent(220, osd)
        }
    } else {
        ; Fade out
        g_alpha := Max(0, g_alpha - 36)
        WinSetTransparent(g_alpha, osd)
        if g_alpha = 0 {
            g_animDir := 0
            g_visible := false
            osd.Hide()
        }
    }
}

; ── OSD HELPERS ─────────────────────────────────────────────────
ShowAction(action_text, hints_text) {
    global g_alpha, g_animDir, g_animCurY, g_visible

    lbl_action.Value := action_text
    lbl_hints.Value  := hints_text

    if !g_visible {
        g_alpha    := 0
        g_animCurY := g_slideY
        osd.Show("x" g_osdX " y" g_slideY " w" OSD_W " h" OSD_H " NoActivate")
        WinSetTransparent(0, osd)
        g_visible := true
    }
    g_animDir := 1

    SetTimer(AutoExit, -TIMEOUT_MS)
}

HideOSD() {
    global g_animDir
    SetTimer(AutoExit, 0)
    g_animDir := -1
}

; ── VOLUME BAR ──────────────────────────────────────────────────
MakeBar(vol) {
    filled := Round(vol / 10)
    bar := ""
    loop 10
        bar .= (A_Index <= filled) ? "█" : "░"
    return "[" bar "]  " vol "%"
}

; ── MODE MANAGEMENT ─────────────────────────────────────────────
EnterMode() {
    global g_mode := true
    ShowAction("◆  MEDIA MODE", "←  prev    →  next    ↑  vol+    ↓  vol−    Space  play")
}

ExitMode() {
    global g_mode := false
    HideOSD()
}

AutoExit() {
    global g_mode := false
    HideOSD()
}

; ── MEDIA COMMANDS ──────────────────────────────────────────────
HINTS := "←  prev    →  next    ↑  vol+    ↓  vol−    Space  play"

DoMedia(action) {
    SetTimer(AutoExit, 0)   ; reset timeout

    switch action {
        case "PREV":
            Send "{Media_Prev}"
            ShowAction("◄◄  PREV TRACK", HINTS)
        case "NEXT":
            Send "{Media_Next}"
            ShowAction("NEXT TRACK  ►►", HINTS)
        case "VOLUP":
            loop VOL_STEP
                Send "{Volume_Up}"
            vol := Round(SoundGetVolume())
            ShowAction("VOL  " MakeBar(vol), HINTS)
        case "VOLDOWN":
            loop VOL_STEP
                Send "{Volume_Down}"
            vol := Round(SoundGetVolume())
            ShowAction("VOL  " MakeBar(vol), HINTS)
        case "PLAY":
            Send "{Media_Play_Pause}"
            ShowAction("▌▌  PLAY / PAUSE", HINTS)
    }

    SetTimer(AutoExit, -TIMEOUT_MS)
}

; ── HOTKEYS ─────────────────────────────────────────────────────
Hotkey STAR_KEY, StarPress

StarPress(*) {
    if !g_mode
        EnterMode()
    else
        ExitMode()
}

#HotIf g_mode
Left::  DoMedia("PREV")
Right:: DoMedia("NEXT")
Up::    DoMedia("VOLUP")
Down::  DoMedia("VOLDOWN")
Space:: DoMedia("PLAY")
Esc:: ExitMode()
#HotIf

; ── KEY DETECTION HELPER ────────────────────────────────────────
; If you don't know your star key name, uncomment the line below,
; reload the script, press your star key, then open:
;   right-click tray icon → View → Key History & Script Info
; Look at the VK (virtual key) or SC (scan code) columns.
;
; ~*F1:: KeyHistory()
