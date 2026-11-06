import Toybox.Application;
import Toybox.Lang;

// Timing modes
const MODE_CIRCUIT = 0;     // laps across one start/finish line
const MODE_SPRINT = 1;      // A-to-B runs of a minute or more (hill climbs, stages)
const MODE_DRAG = 2;        // short A-to-B runs (drag strips, launch tests)
const MODE_COUNT = 3;

const MAX_SPLITS = 2;       // split lines per track: up to three sectors
const MAX_TRACKS = 20;

module ModeInfo {
    function name(mode) as String {
        if (mode == MODE_SPRINT) { return "Sprint"; }
        if (mode == MODE_DRAG) { return "Drag"; }
        return "Circuit";
    }

    function description(mode) as String {
        if (mode == MODE_SPRINT) { return "A to B, 1 min+"; }
        if (mode == MODE_DRAG) { return "Short A to B"; }
        return "Laps";
    }

    // Name used for the FIT activity in Garmin Connect
    function activityName(mode) as String {
        if (mode == MODE_SPRINT) { return "Sprint"; }
        if (mode == MODE_DRAG) { return "Drag"; }
        return "Track Day";
    }
}

// A saved track: its timing mode and timing lines.
class Track {
    var id;             // Number, unique and stable
    var name;           // String
    var mode;           // MODE_*
    var startGate;      // TimingGate or null (start/finish line in circuit mode)
    var finishGate;     // TimingGate or null (sprint and drag)
    var splits;         // Array<TimingGate>, in the order they're crossed

    function initialize(id, name) {
        self.id = id;
        self.name = name;
        mode = MODE_CIRCUIT;
        startGate = null;
        finishGate = null;
        splits = [];
    }

    function isRunMode() as Boolean {
        return mode != MODE_CIRCUIT;
    }

    // Splits are used in circuit and sprint mode; drag runs are too short.
    function usesSplits() as Boolean {
        return mode != MODE_DRAG;
    }

    function activeSplits() as Array {
        return usesSplits() ? splits : [];
    }

    function hasAnyLine() as Boolean {
        return startGate != null || finishGate != null || splits.size() > 0;
    }

    function toStorage() as Dictionary {
        var d = {"name" => name, "mode" => mode};
        if (startGate != null) { d["start"] = startGate.toStorage(); }
        if (finishGate != null) { d["finish"] = finishGate.toStorage(); }
        var sp = [];
        for (var i = 0; i < splits.size(); i++) {
            sp.add(splits[i].toStorage());
        }
        d["splits"] = sp;
        return d;
    }

    static function fromStorage(id, data) {
        if (data == null || !(data instanceof Dictionary)) { return null; }
        var name = data["name"];
        var t = new Track(id, name != null ? name.toString() : "Track " + id);
        var m = data["mode"];
        if (m instanceof Number && m >= 0 && m < MODE_COUNT) { t.mode = m; }
        t.startGate = TimingGate.fromStorage(data["start"], GATE_RADIUS_M);
        t.finishGate = TimingGate.fromStorage(data["finish"], GATE_RADIUS_M);
        var sp = data["splits"];
        if (sp != null && sp instanceof Array) {
            for (var i = 0; i < sp.size() && t.splits.size() < MAX_SPLITS; i++) {
                var g = TimingGate.fromStorage(sp[i], GATE_RADIUS_M);
                if (g != null) { t.splits.add(g); }
            }
        }
        return t;
    }
}

// All-time best for one track in one mode.
class TrackRecord {
    var ms;         // record lap/run time, or null if no record yet (sector bests only)
    var trace;      // LapTrace of the record lap, or null
    var splits;     // cumulative split times (ms) of the record lap, or null
    var sectors;    // best time ever for each sector (ms), or null

    function initialize() {
        ms = null;
        trace = null;
        splits = null;
        sectors = null;
    }

    function toStorage() as Dictionary {
        var d = {};
        if (ms != null) { d["ms"] = ms; }
        if (trace != null) { d["tr"] = trace.pts; }
        if (splits != null) { d["sp"] = splits; }
        if (sectors != null) { d["sec"] = sectors; }
        return d;
    }

    static function fromStorage(data) {
        if (data == null || !(data instanceof Dictionary)) { return null; }
        var r = new TrackRecord();
        r.ms = data["ms"];
        var tr = data["tr"];
        r.trace = (tr != null && tr instanceof Array) ? new LapTrace(tr) : null;
        r.splits = data["sp"];
        r.sectors = data["sec"];
        return r;
    }

    // Sum of the best sectors, or null if any is missing
    function optimalMs() {
        return RaceMath.sum(sectors);
    }
}

module RaceMath {
    // Sum of an array of numbers, or null if the array or any entry is missing
    function sum(arr) {
        if (arr == null || arr.size() == 0) { return null; }
        var total = 0;
        for (var i = 0; i < arr.size(); i++) {
            if (arr[i] == null) { return null; }
            total += arr[i];
        }
        return total;
    }

    // Element-wise minimum of two sector arrays. Returns a new array, or b
    // copied when a is missing or a different length (split count changed).
    function minEach(a, b) as Array {
        var out = [];
        var same = (a != null && a.size() == b.size());
        for (var i = 0; i < b.size(); i++) {
            var v = b[i];
            if (same && a[i] != null && (v == null || a[i] < v)) { v = a[i]; }
            out.add(v);
        }
        return out;
    }

    function sameArray(a, b) as Boolean {
        if (a == null || b == null) { return a == b; }
        if (a.size() != b.size()) { return false; }
        for (var i = 0; i < a.size(); i++) {
            if (a[i] != b[i]) { return false; }
        }
        return true;
    }
}

// Persistence for tracks and their records.
//
// Storage keys:
//   "tracks"          Array of track ids
//   "trackNext"       next id to hand out
//   "currentTrack"    id of the selected track
//   "track_<id>"      Track.toStorage()
//   "rec_<id>_<mode>" TrackRecord.toStorage()
module TrackStore {

    function trackKey(id) as String {
        return "track_" + id.toString();
    }

    function recordKey(id, mode) as String {
        return "rec_" + id.toString() + "_" + mode.toString();
    }

    function ids() as Array {
        var v = Application.Storage.getValue("tracks");
        return (v != null && v instanceof Array) ? v : [];
    }

    function load(id) {
        if (id == null) { return null; }
        return Track.fromStorage(id, Application.Storage.getValue(trackKey(id)));
    }

    function loadAll() as Array {
        var out = [];
        var list = ids();
        for (var i = 0; i < list.size(); i++) {
            var t = load(list[i]);
            if (t != null) { out.add(t); }
        }
        return out;
    }

    // Storage can throw when the object store is full; the track then just
    // isn't persisted, rather than crashing mid-session.
    function save(track) as Void {
        try {
            Application.Storage.setValue(trackKey(track.id), track.toStorage());
        } catch (e) {
        }
    }

    function canCreate() as Boolean {
        return ids().size() < MAX_TRACKS;
    }

    function create(mode) {
        var list = ids();
        var next = Application.Storage.getValue("trackNext");
        if (next == null || !(next instanceof Number)) { next = 1; }
        // Never reuse an id that's still in the list
        while (list.indexOf(next) >= 0) { next++; }
        var t = new Track(next, "Track " + next.toString());
        t.mode = mode;
        list.add(next);
        save(t);
        try {
            Application.Storage.setValue("tracks", list);
            Application.Storage.setValue("trackNext", next + 1);
        } catch (e) {
        }
        return t;
    }

    function remove(id) as Void {
        var list = ids();
        list.remove(id);
        Application.Storage.deleteValue(trackKey(id));
        clearRecords(id, MODE_CIRCUIT);
        try {
            Application.Storage.setValue("tracks", list);
        } catch (e) {
        }
    }

    function loadRecord(id, mode) {
        try {
            return TrackRecord.fromStorage(Application.Storage.getValue(recordKey(id, mode)));
        } catch (e) {
            return null;
        }
    }

    function saveRecord(id, mode, rec) as Void {
        try {
            Application.Storage.setValue(recordKey(id, mode), rec.toStorage());
        } catch (e) {
            // Store full: keep the record in memory for this session only.
        }
    }

    // Records for modes firstMode..last (MODE_CIRCUIT = all, MODE_SPRINT = sprint and drag)
    function hasRecords(id, firstMode) as Boolean {
        for (var m = firstMode; m < MODE_COUNT; m++) {
            if (Application.Storage.getValue(recordKey(id, m)) != null) { return true; }
        }
        return false;
    }

    function clearRecords(id, firstMode) as Void {
        for (var m = firstMode; m < MODE_COUNT; m++) {
            Application.Storage.deleteValue(recordKey(id, m));
        }
    }

    // Split lines changed: sector bests and record splits no longer line up,
    // but the record lap time and trace are still valid.
    function clearSectorRecords(id) as Void {
        for (var m = 0; m < MODE_COUNT; m++) {
            var r = loadRecord(id, m);
            if (r != null && (r.sectors != null || r.splits != null)) {
                r.sectors = null;
                r.splits = null;
                saveRecord(id, m, r);
            }
        }
    }

    // Older versions kept a single set of lines under startGate/finishGate/pointToPoint.
    // Turn that into "Track 1" the first time this version runs.
    function migrateLegacy() as Void {
        if (Application.Storage.getValue("tracks") != null) { return; }
        var start = Application.Storage.getValue("startGate");
        var finish = Application.Storage.getValue("finishGate");
        var p2p = Application.Storage.getValue("pointToPoint");
        if (start == null && finish == null && p2p == null) { return; }

        var t = create(p2p == true ? MODE_SPRINT : MODE_CIRCUIT);
        t.startGate = TimingGate.fromStorage(start, GATE_RADIUS_M);
        t.finishGate = TimingGate.fromStorage(finish, GATE_RADIUS_M);
        save(t);
        Application.Storage.setValue("currentTrack", t.id);
        Application.Storage.deleteValue("startGate");
        Application.Storage.deleteValue("finishGate");
        Application.Storage.deleteValue("pointToPoint");
    }
}
