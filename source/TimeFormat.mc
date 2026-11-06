import Toybox.Lang;

module TimeFormat {

    // 1:23.45
    function lap(ms) as String {
        if (ms == null) { return "-:--.--"; }
        if (ms < 0) { ms = 0; }
        var mins = ms / 60000;
        var secs = (ms % 60000) / 1000;
        var cs = (ms % 1000) / 10;
        return mins.format("%d") + ":" + secs.format("%02d") + "." + cs.format("%02d");
    }

    // 1:23.4 (for the running clock)
    function lapTenths(ms) as String {
        if (ms == null) { return "0:00.0"; }
        if (ms < 0) { ms = 0; }
        var mins = ms / 60000;
        var secs = (ms % 60000) / 1000;
        var tenths = (ms % 1000) / 100;
        return mins.format("%d") + ":" + secs.format("%02d") + "." + tenths.format("%d");
    }

    // 28.4 or 1:02.3 (sector times)
    function short(ms) as String {
        if (ms == null) { return "--"; }
        if (ms < 0) { ms = 0; }
        if (ms < 60000) {
            return (ms / 1000).format("%d") + "." + ((ms % 1000) / 100).format("%d");
        }
        return lapTenths(ms);
    }

    // +0.65 / -1.20
    function delta(ms) as String {
        if (ms == null) { return ""; }
        var sign = ms < 0 ? "-" : "+";
        var a = ms < 0 ? -ms : ms;
        return sign + (a / 1000).format("%d") + "." + ((a % 1000) / 10).format("%02d");
    }

    // 12:34 or 1:02:33
    function duration(ms) as String {
        if (ms == null) { return "--:--"; }
        var total = ms / 1000;
        var h = total / 3600;
        var m = (total % 3600) / 60;
        var s = total % 60;
        if (h > 0) {
            return h.format("%d") + ":" + m.format("%02d") + ":" + s.format("%02d");
        }
        return m.format("%d") + ":" + s.format("%02d");
    }
}
