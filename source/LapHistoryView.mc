import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

const HISTORY_ROWS = 4;

// Lap history (swipe up from the main screen). Newest first. Each row shows
// the lap number, time and gap to best, with a bar showing how far off the
// best it was relative to the slowest lap (or, with split lines, the lap's
// sector times). The best lap is highlighted.
class LapHistoryView extends WatchUi.View {
    var scroll as Number = 0;

    function initialize() {
        View.initialize();
    }

    function maxScroll() as Number {
        var n = getApp().raceSession.laps.size();
        return n > HISTORY_ROWS ? n - HISTORY_ROWS : 0;
    }

    function onUpdate(dc as Dc) as Void {
        var s = getApp().raceSession;
        var h = dc.getHeight();
        var k = h / 416.0;
        var cx = dc.getWidth() / 2;
        var laps = s.laps as Array<Number>;
        var n = laps.size();
        var unit = s.isRunMode() ? "RUN" : "LAP";
        var cj = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var lj = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
        var rj = Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER;

        if (dc has :setAntiAlias) { dc.setAntiAlias(true); }
        dc.setColor(COLOR_BG, COLOR_BG);
        dc.clear();

        // "12 LAPS · OPT 1:23.10" (optimal lap = sum of this session's best sectors)
        var title = n.toString() + " " + unit + (n == 1 ? "" : "S");
        var opt = s.optimalMs();
        if (opt != null) { title += "  ·  OPT " + TimeFormat.lap(opt); }
        dc.setColor(COLOR_MUTED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 50 * k, Graphics.FONT_XTINY, title, cj);

        if (n == 0) {
            dc.setColor(COLOR_DIM, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h / 2, Graphics.FONT_SMALL, "No " + unit.toLower() + "s yet", cj);
            return;
        }

        var best = s.bestLapMs as Number;
        var slowest = laps[0];
        for (var i = 1; i < n; i++) {
            if (laps[i] > slowest) { slowest = laps[i]; }
        }
        var spread = slowest - best;
        if (spread < 1) { spread = 1; }

        var rec = s.referenceMs();
        var bestLine = "BEST " + TimeFormat.lap(best);
        if (rec != null && rec < best) { bestLine += "  REC " + TimeFormat.lap(rec); }
        dc.setColor(COLOR_GOOD, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 80 * k, (rec != null && rec < best) ? Graphics.FONT_XTINY : Graphics.FONT_TINY, bestLine, cj);
        dc.setColor(COLOR_RULE, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(cx - 120 * k, 106 * k, 240 * k, 2);

        var x0 = cx - 150 * k;
        var x1 = cx + 150 * k;
        var barX = x0 + 30 * k;
        var barW = (x1 - x0) - 30 * k;

        for (var r = 0; r < HISTORY_ROWS; r++) {
            var idx = n - 1 - scroll - r;
            if (idx < 0) { break; }
            var lap = laps[idx];
            var isBest = (lap == best);
            var y = (140 + r * 58) * k;

            if (isBest) {
                dc.setColor(0x003C00, Graphics.COLOR_TRANSPARENT);
                dc.fillRoundedRectangle(x0 - 12 * k, y - 26 * k, (x1 - x0) + 24 * k, 54 * k, 14 * k);
            }
            dc.setColor(isBest ? COLOR_GOOD : COLOR_MUTED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x0, y - 4 * k, Graphics.FONT_TINY, (idx + 1).toString(), lj);
            dc.setColor(isBest ? COLOR_GOOD : Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx - 6 * k, y - 4 * k, Graphics.FONT_SMALL, TimeFormat.lap(lap), cj);
            dc.setColor(isBest ? COLOR_GOOD : COLOR_BAD, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x1, y - 4 * k, Graphics.FONT_TINY, isBest ? "BEST" : TimeFormat.delta(lap - best), rj);

            // Sector times in place of the bar when every split was crossed;
            // the session's best sector times are green.
            var sec = (idx < s.lapSectors.size()) ? s.lapSectors[idx] : null;
            if (sec != null) {
                var bs = s.bestSectors;
                var cols = sec.size();
                for (var j = 0; j < cols; j++) {
                    var sx = barX + barW * (2 * j + 1) / (2 * cols);
                    var top = (bs != null && j < bs.size() && bs[j] == sec[j]);
                    dc.setColor(top ? COLOR_GOOD : COLOR_MUTED, Graphics.COLOR_TRANSPARENT);
                    dc.drawText(sx, y + 20 * k, Graphics.FONT_XTINY, TimeFormat.short(sec[j]), cj);
                }
                continue;
            }

            // Gap-to-best bar (empty for the best lap)
            dc.setColor(COLOR_RULE, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(barX, y + 18 * k, barW, 4, 2);
            if (!isBest) {
                var frac = (lap - best).toFloat() / spread;
                var fw = barW * frac;
                if (fw < 4) { fw = 4; }
                dc.setColor(frac > 0.5 ? COLOR_BAD : Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
                dc.fillRoundedRectangle(barX, y + 18 * k, fw, 4, 2);
            }
        }

        // Scroll hints
        dc.setColor(COLOR_DIM, Graphics.COLOR_TRANSPARENT);
        if (scroll > 0) {
            var ty = 118 * k;
            dc.fillPolygon([[cx, ty - 5], [cx - 8, ty + 5], [cx + 8, ty + 5]]);
        }
        if (scroll < maxScroll()) {
            var by = 388 * k;
            dc.fillPolygon([[cx, by + 5], [cx - 8, by - 5], [cx + 8, by - 5]]);
        }
    }
}

class LapHistoryDelegate extends WatchUi.BehaviorDelegate {
    private var _view as LapHistoryView;

    function initialize(view as LapHistoryView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onNextPage() as Boolean {
        if (_view.scroll < _view.maxScroll()) {
            _view.scroll++;
            WatchUi.requestUpdate();
        }
        return true;
    }

    function onPreviousPage() as Boolean {
        if (_view.scroll > 0) {
            _view.scroll--;
            WatchUi.requestUpdate();
        } else {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        }
        return true;
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }
}
