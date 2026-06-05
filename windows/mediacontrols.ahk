#Requires AutoHotkey v2.0
#SingleInstance Force
SetWorkingDir A_ScriptDir

; ╔══════════════════════════════════════════════════════════════╗
; ║  9i Media Controls  —  Windows                              ║
; ║                                                              ║
; ║  Press the star key to enter MEDIA MODE, then:              ║
; ║    ←  Previous track      →  Next track                     ║
; ║    ↑  Play / Pause        ↓  Stop                          ║
; ║    Esc  Exit mode                                           ║
; ║                                                              ║
; ║  Run this script once, then press the star key and check    ║
; ║  View → Key History in the tray icon to find STAR_KEY.      ║
; ╚══════════════════════════════════════════════════════════════╝

; ── CONFIGURATION ───────────────────────────────────────────────
;  To find your star key name: right-click the AHK tray icon,
;  open "Key History", press the key, look at the VK/SC column.
;  Common values for Yoga function keys: F20, F21, F22, Browser_Favorites
STAR_KEY       := "^!+k" ; Ctrl+Alt+Shift+K — swap for your star key when sorted
TIMEOUT_ENTER  := 2000   ; ms before mode exits after entering (no key pressed)
TIMEOUT_ACTION := 800    ; ms before mode exits after each action

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
osd.SetFont("s" OSD_FS2 " c" COL_DIM " Bold", OSD_FONT)
global lbl_hints := osd.Add("Text", "x0 y" (OSD_H - 28) " w" OSD_W " h22 Center +0x200", "")

; Compute position: bottom-centre of working area
MonitorGetWorkArea(, &mL, &mT, &mR, &mB)
global g_scrW  := mR - mL
global g_osdX  := mL + (g_scrW - OSD_W) // 2
global g_osdY  := mB - OSD_H - 40          ; final Y when shown
global g_slideY := g_osdY + 28             ; start Y (slides up from here)

; Prime the window in Windows' memory so the first real Show is instant,
; and set transparency once here rather than on every Show call.
osd.Show("x" g_osdX " y" g_osdY " w" OSD_W " h" OSD_H " NoActivate")
WinSetTransparent(0, osd)
osd.Hide()

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
ShowAction(action_text, hints_text, timeout_ms) {
    global g_alpha, g_animDir, g_animCurY, g_visible

    lbl_action.Value := action_text
    lbl_hints.Value  := hints_text

    if !g_visible {
        g_alpha    := 220
        g_animCurY := g_osdY
        osd.Show("x" g_osdX " y" g_osdY " w" OSD_W " h" OSD_H " NoActivate")
        WinSetTransparent(220, osd)
        g_visible := true
    }
    g_animDir := 0  ; no fade-in — appear instantly, only fade out on exit

    SetTimer(AutoExit, -timeout_ms)
}

HideOSD() {
    global g_animDir
    SetTimer(AutoExit, 0)
    g_animDir := -1
}

; ── MODE MANAGEMENT ─────────────────────────────────────────────
EnterMode() {
    global g_mode := true
    ShowAction("◆  MEDIA MODE", HINTS, TIMEOUT_ENTER)
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
HINTS := "← prev  → next  ↑ play/pause  ↓ stop  Esc exit"

DoMedia(action) {
    Critical "On"   ; high priority — don't let other threads interrupt mid-action
    SetTimer(AutoExit, 0)

    switch action {
        case "PREV":
            Send "{Media_Prev}"
            ShowAction("◄◄  PREV TRACK", HINTS, TIMEOUT_ACTION)
        case "NEXT":
            Send "{Media_Next}"
            ShowAction("NEXT TRACK  ►►", HINTS, TIMEOUT_ACTION)
        case "PLAYPAUSE":
            Send "{Media_Play_Pause}"
            ShowAction("▌▌  PLAY / PAUSE", HINTS, TIMEOUT_ACTION)
        case "STOP":
            Send "{Media_Stop}"
            ShowAction("■  STOP", HINTS, TIMEOUT_ACTION)

    }
}

; ── HOTKEYS ─────────────────────────────────────────────────────
; Static hotkey — if you change STAR_KEY to a bare key name (e.g. "F20")
; switch this back to:  Hotkey STAR_KEY, StarPress
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
Up::    DoMedia("PLAYPAUSE")
Down::  DoMedia("STOP")
Esc:: ExitMode()
#HotIf

; ── KEY DETECTION HELPER ────────────────────────────────────────
; If you don't know your star key name, uncomment the line below,
; reload the script, press your star key, then open:
;   right-click tray icon → View → Key History & Script Info
; Look at the VK (virtual key) or SC (scan code) columns.
;
; ~*F1:: KeyHistory()
