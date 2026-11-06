import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Position;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

const LAP_FLASH_MS = 6000;   // how long a completed lap stays on the big display
const SPLIT_FLASH_MS = 4000; // how long a split time stays in the pill

// Shared colours
const COLOR_BG     = Graphics.COLOR_BLACK;
const COLOR_DIM    = Graphics.COLOR_DK_GRAY;
const COLOR_MUTED  = Graphics.COLOR_LT_GRAY;
const COLOR_GOOD   = Graphics.COLOR_GREEN;
const COLOR_WARN   = Graphics.COLOR_YELLOW;
const COLOR_BAD    = Graphics.COLOR_RED;
const COLOR_ACCENT = 0x00AAFF;
const COLOR_TRACK  = 0x202020;
const COLOR_RULE   = 0x282828;
const COLOR_PANEL  = 0x181818;

// Main race screen, laid out for the Venu 2's 416 px round display using the
// device's real font metrics. Five zones, top to bottom:
//
//   header   ● LAP 5 ▂▄▆        state + lap number + GPS
//   hero       1:01.2           running lap (completed lap for 6 s)
//   pill    (    -0.32    )     live delta to the track record / split / prompt
//   stats   BEST · L3 |  HR
//           1:23.45   | ♥ 142
//   footer  12:34 · 148 km/h
//
// Bezel ring: how far round the track record lap you are, green while ahead
// of it and red while behind.
// All y positions are designed at 416 px and scaled for other screen sizes.
class GarminRace2View extends WatchUi.View {
    private var _timer;
    private var _ticks as Number = 0;

    function initialize() {
        View.initialize();
    }

    function onShow() as Void {
        _timer = new Timer.Timer();
        _timer.start(method(:onTick), 100, true);
    }

    function onHide() as Void {
        if (_timer != null) {
            _timer.stop();
            _timer = null;
        }
    }

    // 10 Hz while a lap is running, 2 Hz while armed (blinking dot), else 1 Hz.
    function onTick() as Void {
        _ticks++;
        var s = getApp().raceSession;
        if (s.lapStartMs != null || (s.isRecording && _ticks % 5 == 0) || _ticks % 10 == 0) {
            WatchUi.requestUpdate();
        }
    }

    function onUpdate(dc as Dc) as Void {
        var s = getApp().raceSession;
        var w = dc.getWidth();
        var h = dc.getHeight();
        var k = h / 416.0;               // layout scale
        var cx = w / 2;
        var now = System.getTimer();
        var runMode = s.isRunMode();
        var tr = s.track;
        var unit = runMode ? "RUN " : "LAP ";
        var blinkOn = (now / 500) % 2 == 0;

        if (dc has :setAntiAlias) { dc.setAntiAlias(true); }
        dc.setColor(COLOR_BG, COLOR_BG);
        dc.clear();

        var flashing = s.lastLapCompletedMs != null && s.laps.size() > 0
            && (now - s.lastLapCompletedMs) < LAP_FLASH_MS;

        // ---- Work out what each zone shows ----
        var head;  var headColor = Graphics.COLOR_WHITE;
        var dotColor = null;                       // null = no dot
        var big;   var bigColor = Graphics.COLOR_WHITE;
        var pillText = null; var pillFont = Graphics.FONT_TINY;
        var pillFg = COLOR_MUTED; var pillBg = null; var pillOutline = null;
        var ring = null; var ringColor = COLOR_ACCENT;

        if (flashing) {
            big = TimeFormat.lap(s.getLastLapMs());
            dotColor = COLOR_BAD;
            ring = 1.0;
            pillFont = Graphics.FONT_SMALL;
            pillFg = Graphics.COLOR_BLACK;
            // Pill: gap to the track record as it stood before this lap.
            if (s.lastDeltaMs == null) {
                pillBg = COLOR_GOOD;
                pillText = runMode ? "FIRST RUN" : "FIRST LAP";
            } else {
                pillBg = s.lastDeltaMs < 0 ? COLOR_GOOD : COLOR_BAD;
                pillText = TimeFormat.delta(s.lastDeltaMs);
            }
            if (s.lastLapWasRecord) {
                head = "NEW RECORD";
                headColor = COLOR_GOOD;
                bigColor = COLOR_GOOD;
                ringColor = COLOR_GOOD;
            } else if (s.lastLapWasBest) {
                head = "SESSION BEST";
                headColor = COLOR_GOOD;
                bigColor = COLOR_GOOD;
                ringColor = COLOR_GOOD;
            } else {
                head = unit + s.laps.size().toString() + " DONE";
                bigColor = COLOR_WARN;
                ringColor = COLOR_WARN;
            }
        } else if (s.lapStartMs != null) {
            head = unit + (s.laps.size() + 1).toString();
            dotColor = blinkOn ? COLOR_BAD : null;
            var cur = s.getCurrentLapMs();
            big = TimeFormat.lapTenths(cur);
            var ref = s.referenceMs();
            var p = s.getLapProgress();
            var splitFlash = s.lastSplitIndex != null && s.lastSplitAtMs != null
                && (now - s.lastSplitAtMs) < SPLIT_FLASH_MS;

            ring = (p != null && p > 1.0) ? 1.0 : p;
            if (s.liveDeltaMs != null) {
                ringColor = s.liveDeltaMs < 0 ? COLOR_GOOD : COLOR_BAD;
            } else if (p != null && p > 1.0) {
                ringColor = COLOR_BAD;
            }

            if (splitFlash) {
                // Just crossed a split: its gap to the record lap's split
                var sd = s.lastSplitDeltaMs;
                pillFont = Graphics.FONT_SMALL;
                if (sd != null) {
                    pillText = "S" + s.lastSplitIndex.toString() + "  " + TimeFormat.delta(sd);
                    pillFg = Graphics.COLOR_BLACK;
                    pillBg = sd < 0 ? COLOR_GOOD : COLOR_BAD;
                } else {
                    pillText = "S" + s.lastSplitIndex.toString() + "  " + TimeFormat.lap(s.lastSplitMs);
                    pillFg = Graphics.COLOR_WHITE;
                    pillBg = COLOR_PANEL;
                }
            } else if (s.liveDeltaMs != null) {
                // Live gap to the record lap at this point on track
                pillText = TimeFormat.delta(s.liveDeltaMs);
                pillFont = Graphics.FONT_SMALL;
                pillFg = Graphics.COLOR_BLACK;
                pillBg = s.liveDeltaMs < 0 ? COLOR_GOOD : COLOR_BAD;
            } else if (ref != null && cur > ref) {
                // Already slower than the record lap
                pillText = TimeFormat.delta(cur - ref);
                pillFont = Graphics.FONT_SMALL;
                pillFg = Graphics.COLOR_BLACK;
                pillBg = COLOR_BAD;
            } else {
                var last = s.getLastLapMs();
                pillText = last != null ? "LAST " + TimeFormat.lap(last)
                                        : (runMode ? "TIMING RUN" : "FIRST TIMED LAP");
                pillBg = COLOR_PANEL;
            }
        } else if (s.isRecording) {
            head = "ARMED";
            headColor = COLOR_WARN;
            dotColor = blinkOn ? COLOR_WARN : null;
            big = "0:00.0";
            bigColor = COLOR_DIM;
            pillText = runMode ? "CROSS START LINE" : "CROSS LINE TO START";
            pillFg = COLOR_WARN;
            pillOutline = COLOR_WARN;
        } else {
            head = ModeInfo.name(s.mode()).toUpper();
            headColor = COLOR_MUTED;
            big = "0:00.0";
            bigColor = COLOR_DIM;
            if (tr.startGate == null) {
                pillText = runMode ? "SET START IN MENU" : "SET LINE IN MENU";
                pillFg = Graphics.COLOR_ORANGE;
                pillOutline = Graphics.COLOR_ORANGE;
            } else if (runMode && tr.finishGate == null) {
                pillText = "SET FINISH IN MENU";
                pillFg = Graphics.COLOR_ORANGE;
                pillOutline = Graphics.COLOR_ORANGE;
            } else if (s.sessionStartMs != null) {
                pillText = "SAVED  ·  " + s.laps.size().toString() + (runMode ? " RUNS" : " LAPS");
                pillBg = COLOR_PANEL;
            } else {
                pillText = "PRESS START";
                pillFg = Graphics.COLOR_WHITE;
                pillOutline = COLOR_MUTED;
            }
        }

        // ---- Draw ----
        drawRing(dc, w, h, ring, ringColor, 8);
        drawHeader(dc, cx, 62 * k, head, headColor, dotColor, s.gpsQuality);

        var heroFont = Graphics.FONT_NUMBER_HOT;
        if (dc.getTextWidthInPixels(big, heroFont) > w * 0.86) {
            heroFont = Graphics.FONT_NUMBER_MEDIUM;
        }
        dc.setColor(bigColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 152 * k, heroFont, big, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        if (pillText != null) {
            drawPill(dc, cx, 236 * k, 40 * k, pillText, pillFont, pillFg, pillBg, pillOutline);
        }

        // Divider
        dc.setColor(COLOR_RULE, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(cx - 130 * k, 272 * k, 260 * k, 2);

        // Stats: BEST | HR
        var bx = cx - 78 * k;
        var hx = cx + 82 * k;
        var capY = 296 * k;
        var valY = 328 * k;
        var cj = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        // Session best once there is one, otherwise the track record to beat
        var bestCap = "BEST";
        var bestVal = s.bestLapMs;
        var bestColor = COLOR_GOOD;
        if (bestVal == null && s.referenceMs() != null) {
            bestCap = "RECORD";
            bestVal = s.referenceMs();
            bestColor = COLOR_ACCENT;
        } else if (s.bestLapMs != null && s.laps.size() > 1) {
            var n = s.getBestLapNumber();
            if (n != null) { bestCap = "BEST  ·  " + (runMode ? "R" : "L") + n.toString(); }
        }
        dc.setColor(COLOR_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(bx, capY, Graphics.FONT_XTINY, bestCap, cj);
        dc.setColor(bestVal != null ? bestColor : COLOR_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(bx, valY, Graphics.FONT_SMALL, TimeFormat.lap(bestVal), cj);

        dc.setColor(COLOR_RULE, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(cx + 2 * k, 292 * k, 2, 52 * k);

        dc.setColor(COLOR_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(hx, capY, Graphics.FONT_XTINY, "HR", cj);
        var hrText = s.heartRate != null ? s.heartRate.toString() : "--";
        var hrW = dc.getTextWidthInPixels(hrText, Graphics.FONT_SMALL);
        drawHeart(dc, hx - hrW / 2 - 8 * k, valY, 18 * k, hrColor(s));
        dc.setColor(s.heartRate != null ? Graphics.COLOR_WHITE : COLOR_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(hx + 10 * k, valY, Graphics.FONT_SMALL, hrText, cj);

        // Footer
        var metric = System.getDeviceSettings().distanceUnits != System.UNIT_STATUTE;
        var spd = (s.speed != null ? (s.speed * (metric ? 3.6 : 2.23694) + 0.5).toNumber().toString() : "--")
                + (metric ? " km/h" : " mph");
        var footer;
        if (s.isRecording) {
            footer = TimeFormat.duration(s.getSessionMs()) + "  ·  " + spd;
        } else {
            var name = tr.name;
            if (name.length() > 12) { name = name.substring(0, 12); }
            footer = name + "  ·  " + spd;
        }
        dc.setColor(COLOR_MUTED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 378 * k, Graphics.FONT_XTINY, footer, cj);
    }

    // ------------------------------------------------------------------

    // Thin track around the bezel, with a thick progress arc from 12 o'clock.
    private function drawRing(dc as Dc, w, h, p, color, pen) as Void {
        var cx = w / 2;
        var cy = h / 2;
        var r = w / 2 - 4;
        dc.setPenWidth(4);
        dc.setColor(COLOR_TRACK, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(cx, cy, r);
        if (p == null || p <= 0.0) { return; }

        dc.setPenWidth(pen);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        var sweep = (360.0 * p).toNumber();
        if (sweep >= 360) {
            dc.drawCircle(cx, cy, r);
        } else {
            if (sweep < 2) { sweep = 2; }
            dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, 90, 90 - sweep);
        }
    }

    // ● LABEL ▂▄▆ centred as one group.
    private function drawHeader(dc as Dc, cx, y, text as String, color, dotColor, q) as Void {
        var font = Graphics.FONT_TINY;
        var tw = dc.getTextWidthInPixels(text, font);
        var dotR = 7;
        var total = dotR * 2 + 10 + tw + 14 + 21;
        var x = cx - total / 2;

        if (dotColor != null) {
            dc.setColor(dotColor, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x + dotR, y, dotR);
        }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + dotR * 2 + 10, y, font, text, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        drawGpsBars(dc, x + dotR * 2 + 10 + tw + 14, y, q);
    }

    // Three signal bars, coloured by fix quality; red slash when there's no fix.
    private function drawGpsBars(dc as Dc, x, y, q) as Void {
        var bars = 0;
        var color = COLOR_BAD;
        if (q == Position.QUALITY_GOOD)        { bars = 3; color = COLOR_GOOD; }
        else if (q == Position.QUALITY_USABLE) { bars = 2; color = COLOR_WARN; }
        else if (q == Position.QUALITY_POOR)   { bars = 1; color = Graphics.COLOR_ORANGE; }

        for (var i = 0; i < 3; i++) {
            var bh = 7 + i * 5;
            dc.setColor(i < bars ? color : 0x303030, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(x + i * 8, y + 9 - bh, 5, bh, 1);
        }
        if (bars == 0) {
            dc.setColor(COLOR_BAD, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(2);
            dc.drawLine(x - 2, y + 10, x + 23, y - 10);
        }
    }

    // Rounded pill with centred text; filled (bg) or outlined.
    private function drawPill(dc as Dc, cx, y, ph, text as String, font, fg, bg, outline) as Void {
        var pw = dc.getTextWidthInPixels(text, font) + 40;
        var x = cx - pw / 2;
        var top = y - ph / 2;
        var rad = ph / 2;
        if (outline != null) {
            dc.setColor(outline, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(x, top, pw, ph, rad);
            dc.setColor(COLOR_BG, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(x + 2, top + 2, pw - 4, ph - 4, rad - 2);
        } else if (bg != null) {
            dc.setColor(bg, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(x, top, pw, ph, rad);
        }
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, font, text, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Small heart: two circles and a triangle.
    private function drawHeart(dc as Dc, x, y, size, color) as Void {
        var r = size * 0.28;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x - r, y - r * 0.4, r);
        dc.fillCircle(x + r, y - r * 0.4, r);
        dc.fillPolygon([[x - 2 * r, y - r * 0.15], [x + 2 * r, y - r * 0.15], [x, y + size * 0.55]]);
    }

    private function hrColor(s) {
        if (s.heartRate == null) { return COLOR_DIM; }
        var z = s.getHeartRateZone();
        if (z == null || z <= 1) { return Graphics.COLOR_WHITE; }
        if (z == 2) { return COLOR_ACCENT; }
        if (z == 3) { return COLOR_GOOD; }
        if (z == 4) { return Graphics.COLOR_ORANGE; }
        return COLOR_BAD;
    }
}
