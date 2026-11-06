import Toybox.Lang;
import Toybox.Math;

const MAX_TRACE_PTS = 900;          // 15 min at 1 Hz; keeps a stored record well under 32 KB
const MATCH_RADIUS_M = 40.0;        // further than this from the record line = off track, no delta
const MATCH_LOOKAHEAD = 30;         // points searched ahead of the last match

// The path of one lap: a point per GPS fix with the time into the lap.
//
// Positions are metres east/north of the start line (the start gate's local
// frame), stored as whole decimetres so a record lap packs into Storage as a
// flat array: [x0, y0, t0, x1, y1, t1, ...].
//
// For the live delta, the record lap's trace is asked "how long into the lap
// were you at this spot?" for each new fix. The search follows a cursor
// forward along the trace, so a part of the track that runs close to another
// (a hairpin, a parallel straight) isn't confused with it.
class LapTrace {
    var pts as Array;
    private var _cursor as Number = 0;

    function initialize(data) {
        pts = (data != null) ? data : [];
    }

    function size() as Number {
        return pts.size() / 3;
    }

    // x, y in metres; t in ms since the lap started
    function add(x, y, t) as Void {
        if (pts.size() >= MAX_TRACE_PTS * 3) { return; }
        pts.add((x * 10.0).toNumber());
        pts.add((y * 10.0).toNumber());
        pts.add(t.toNumber());
    }

    function resetCursor() as Void {
        _cursor = 0;
    }

    // Time into this lap (ms) at the point nearest (x, y), interpolated
    // between fixes; -1 if no part of the lap is within MATCH_RADIUS_M.
    function timeAt(x, y) as Number {
        var n = size();
        if (n < 2) { return -1; }
        var px = (x * 10.0).toFloat();      // to decimetres
        var py = (y * 10.0).toFloat();
        var r2 = MATCH_RADIUS_M * 10.0 * MATCH_RADIUS_M * 10.0;

        var lo = _cursor - 2;
        if (lo < 0) { lo = 0; }
        var hi = _cursor + MATCH_LOOKAHEAD;
        if (hi > n - 1) { hi = n - 1; }
        var best = nearest(px, py, lo, hi);
        if (best[1] > r2) {
            // Lost the thread (GPS gap, off track): search the whole lap once.
            best = nearest(px, py, 0, n - 1);
            if (best[1] > r2) { return -1; }
        }
        var i = best[0] as Number;
        _cursor = i;

        // Interpolate along whichever neighbouring segment the point lies on.
        var after = (i < n - 1) ? project(px, py, i) : null;
        var before = (i > 0) ? project(px, py, i - 1) : null;
        var seg = after;
        var from = i;
        if (seg == null || (before != null && before[1] < seg[1])) {
            seg = before;
            from = i - 1;
        }
        var t0 = pts[from * 3 + 2];
        var t1 = pts[from * 3 + 5];
        return (t0 + seg[0] * (t1 - t0)).toNumber();
    }

    // [index, squaredDistance] of the point in lo..hi closest to (px, py)
    private function nearest(px, py, lo, hi) as Array {
        var bi = lo;
        var bd = -1.0;
        for (var i = lo; i <= hi; i++) {
            var dx = pts[i * 3] - px;
            var dy = pts[i * 3 + 1] - py;
            var d = dx * dx + dy * dy;
            if (bd < 0 || d < bd) {
                bd = d;
                bi = i;
            }
        }
        return [bi, bd];
    }

    // [fraction 0..1, squaredDistance] of (px, py) projected onto segment i -> i+1
    private function project(px, py, i) as Array {
        var ax = pts[i * 3].toFloat();
        var ay = pts[i * 3 + 1].toFloat();
        var dx = pts[i * 3 + 3] - ax;
        var dy = pts[i * 3 + 4] - ay;
        var len2 = dx * dx + dy * dy;
        var f = 0.0;
        if (len2 > 0) {
            f = ((px - ax) * dx + (py - ay) * dy) / len2;
            if (f < 0) { f = 0.0; }
            if (f > 1) { f = 1.0; }
        }
        var ex = ax + f * dx - px;
        var ey = ay + f * dy - py;
        return [f, ex * ex + ey * ey];
    }
}
