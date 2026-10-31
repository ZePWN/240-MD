-- Screen saver for 240-MP: bounces the 240-MD logo across a solid black
-- background when the video has been paused longer than the configured timeout.
--
-- Loaded by --script= only when screensaver_timeout != "OFF".
-- Uses the same ASS-overlay technique as mpv-media-keys.lua's volume bar.
-- Dismiss keys are consumed, matching the app-shell overlay: the first press
-- only wakes the screen saver, the next press acts normally.

local assdraw = require("mp.assdraw")

-- Raw script-opts key (same convention as mpv-osc.lua's transcode-offset);
-- mp.options.read_options would instead expect a "screensaver-" prefix.
local timeout_sec = tonumber(mp.get_opt("screensaver_timeout") or "60") or 60
local SPEED = 2

-- ─── logo ─────────────────────────────────────────────────────────────────────
-- Vector copy of assets/images/logo.svg (24x24 units, straight segments only,
-- filled white) so the mpv screen saver bounces the same mark as the QML one.
-- Subpath windings alternate, so the mask cutout and the shape inside it render
-- as hole / fill under both the even-odd and nonzero fill rules.
local LOGO_UNITS_W, LOGO_UNITS_H = 24, 24
local LOGO_SUBPATHS = {
        { 14,0, 30,0, 30,2, 32,2, 32,4, 34,4, 34,20, 32,20, 32,22,
            30,22, 30,24, 14,24, 14,22, 12,22, 12,20, 10,20, 10,4,
            12,4, 12,2, 14,2 },
        { 20,6, 18,6, 18,7, 16,7, 16,9, 15,9, 15,15, 16,15,
            16,17, 18,17, 18,18, 20,18, 20,19, 24,19, 24,18,
            26,18, 26,17, 28,17, 28,15, 29,15, 29,9, 28,9, 28,7,
            26,7, 26,6, 24,6, 24,5, 20,5 },
        { 13,7, 13,17, 16,17, 16,7 },
        { 21,10, 23,10, 23,11, 24,11, 24,13, 23,13, 23,14,
            21,14, 21,13, 20,13, 20,11, 21,11 },
}

-- Build the ASS drawing string at a pixel scale, origin 0,0 (\pos moves it)
local function logo_drawing(scale)
    local parts = {}
    for _, sp in ipairs(LOGO_SUBPATHS) do
        for i = 1, #sp, 2 do
            parts[#parts + 1] = string.format("%s%.1f %.1f",
                i == 1 and "m " or "l ", (sp[i] - 10) * scale, sp[i + 1] * scale)
        end
    end
    return table.concat(parts, " ")
end

-- ─── state ───────────────────────────────────────────────────────────────────
local ss_active   = false
local paused_sec  = 0
local x, y   = 20, 20
local vx, vy = SPEED, SPEED
-- Set at activation: logo sized to 5% of OSD width (matching the QML overlay's
-- sourceSize of root.sw * 0.05), drawing pre-scaled to pixels.
local logo_w, logo_h = 0, 0
local logo_path = ""

-- ─── forward declarations ─────────────────────────────────────────────────────
local activate, dismiss, anim_timer

-- ─── ASS overlay ──────────────────────────────────────────────────────────────
local overlay = mp.create_osd_overlay("ass-events")

-- ─── draw full frame ─────────────────────────────────────────────────────────
local function draw_frame(w, h, tx, ty)
    local a = assdraw.ass_new()
    -- Solid black background covering the entire OSD area
    a:new_event()
    a:pos(0, 0)
    a:append(string.format(
        "{\\bord0\\shad0\\1c&H000000&\\1a&H00&\\p1}m 0 0 l %d 0 l %d %d l 0 %d{\\p0}",
        w, w, h, h
    ))
    -- Bouncing logo on top
    a:new_event()
    a:append(string.format(
        "{\\an7\\pos(%d,%d)\\bord0\\shad0\\1c&HFFFFFF&\\p1}%s{\\p0}",
        math.floor(tx), math.floor(ty), logo_path
    ))
    overlay.res_x = w
    overlay.res_y = h
    overlay.data  = a.text
    overlay:update()
end

-- ─── key bindings ─────────────────────────────────────────────────────────────
-- Any key a user would press while interacting with mpv playback should wake
-- the screen saver, matching the menu-side overlay's "any key dismisses"
-- behavior (Main.qml). Includes both navigation keys and the HID media-key
-- names mpv-media-keys.lua binds (PLAYPAUSE etc.) — otherwise e.g. a hardware
-- Play press falls straight through to mpv-media-keys.lua and resumes playback
-- behind the still-active screen saver.
local DISMISS_KEYS = {
    "SPACE", "ENTER", "KP_ENTER", "ESC",
    "LEFT", "RIGHT", "UP", "DOWN", "PGUP", "PGDWN",
    "HOME", "END",
    "MBTN_LEFT", "MBTN_RIGHT",
    "PLAYPAUSE", "STOP", "FORWARD", "REWIND", "NEXT", "PREV",
    "VOLUME_UP", "VOLUME_DOWN", "MUTE",
}

activate = function()
    if ss_active then return end
    ss_active = true

    local ww, wh = mp.get_osd_size()
    if ww == 0 then ww = 640 end
    if wh == 0 then wh = 480 end

    local scale = (ww * 0.1) / LOGO_UNITS_W
    logo_w = LOGO_UNITS_W * scale
    logo_h = LOGO_UNITS_H * scale
    logo_path = logo_drawing(scale)

    x = math.floor(math.random() * math.max(1, ww - logo_w))
    y = math.floor(math.random() * math.max(1, wh - logo_h))
    vx = SPEED
    vy = SPEED

    for _, k in ipairs(DISMISS_KEYS) do
        mp.add_forced_key_binding(k, "ss-dismiss-" .. k, dismiss)
    end

    draw_frame(ww, wh, x, y)
    anim_timer:resume()
end

dismiss = function()
    if not ss_active then return end
    ss_active = false
    paused_sec = 0

    overlay:remove()
    anim_timer:kill()

    for _, k in ipairs(DISMISS_KEYS) do
        pcall(mp.remove_key_binding, "ss-dismiss-" .. k)
    end
end

-- ─── 1-second tick: count up while paused ────────────────────────────────────
local pause_monitor = mp.add_periodic_timer(1.0, function()
    if ss_active then return end
    local is_paused = mp.get_property_native("pause")
    if is_paused then
        paused_sec = paused_sec + 1
        if paused_sec >= timeout_sec then
            activate()
        end
    else
        paused_sec = 0
    end
end)

-- ─── ~60 fps animation ───────────────────────────────────────────────────────
anim_timer = mp.add_periodic_timer(0.016, function()
    if not ss_active then return end

    local ww, wh = mp.get_osd_size()
    if ww == 0 or wh == 0 then return end

    x = x + vx
    y = y + vy

    if x + logo_w > ww then
        x = ww - logo_w
        vx = -math.abs(vx)
    elseif x < 0 then
        x = 0
        vx = math.abs(vx)
    end

    if y + logo_h > wh then
        y = wh - logo_h
        vy = -math.abs(vy)
    elseif y < 0 then
        y = 0
        vy = math.abs(vy)
    end

    draw_frame(ww, wh, x, y)
end)
anim_timer:kill()
