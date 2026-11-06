import Toybox.Activity;
import Toybox.ActivityRecording;
import Toybox.Application;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.System;
import Toybox.UserProfile;

const GATE_RADIUS_M = 25.0;      // capture radius around a timing line point
const MIN_LAP_MS = 10000;        // circuit: ignore start/finish crossings sooner than this into a lap
const SPRINT_MIN_RUN_MS = 60000; // sprint: ignore finish crossings sooner than this into a run
const DRAG_MIN_RUN_MS = 1000;    // drag: only rule out impossible sub-second runs
const MIN_SPLIT_MS = 2000;       // ignore split crossings this soon after the lap start or the previous split
const MIN_HEADING_SPEED = 3.0;   // m/s; below this GPS heading is unreliable
const MIN_CROSS_SPEED = 1.5;     // m/s; slower than this (parked, walking) never counts as a crossing
const MAX_FIX_GAP_MS = 4000;     // don't interpolate a crossing across a GPS dropout longer than this
const AUTO_TRACK_RADIUS_M = 5000.0; // pick a saved track automatically if its start line is this close

const EVENT_NONE = 0;
const EVENT_TIMING_STARTED = 1;
const EVENT_LAP_COMPLETED = 2;
const EVENT_SPLIT = 3;
const EVENT_TRACK_CHANGED = 4;

// Result of setting a line
const LINE_FAILED = 0;           // no GPS fix
const LINE_SET = 1;
const LINE_SET_RECORD_RESET = 2; // set, and the track's old records were cleared

// Holds track setup, live sensor data and lap timing.
// All timing uses System.getTimer() (milliseconds) for sub-second precision.
class RaceSessionModel {
    // --- Track setup (persisted) ---
    var track;              // Track, always set
    var record;             // TrackRecord for this track and mode, or null

    // --- Live data ---
    var currentLocation;    // Position.Location or null
    var speed;              // m/s or null
    var heading;            // radians or null
    var gpsQuality;         // Position.Quality
    var heartRate;          // bpm or null
    var maxHeartRate;       // bpm or null (this session)
    var hrZones;            // Array of 6 zone boundaries from the user profile, or null

    // --- Timing ---
    var isRecording;
    var sessionStartMs;
    var sessionEndMs;
    var lapStartMs;         // null while armed and waiting to cross the start line
    var laps;               // Array<Number> of completed lap/run times in ms
    var lapSectors;         // per lap: Array<Number> of sector times, or null if a split was missed
    var bestLapMs;          // best this session
    var bestSectors;        // best sector times this session, or null
    var lastDeltaMs;        // last lap minus the track record before it (negative = faster)
    var lastLapWasBest;     // best of the session
    var lastLapWasRecord;   // new all-time track record
    var lastLapCompletedMs;
    var liveDeltaMs;        // current lap vs the record lap at the same point on track, or null
    var liveProgress;       // fraction of the record lap covered so far, or null
    var lastSplitIndex;     // 1-based split crossed last, or null
    var lastSplitDeltaMs;   // that split vs the record lap's, or null
    var lastSplitMs;        // that split's time into the lap
    var lastSplitAtMs;      // System.getTimer() when it was crossed

    // Previous and current fix (radians, ms) for the segment being checked
    private var _lat0;
    private var _lon0;
    private var _ms0;
    private var _lat1;
    private var _lon1;
    private var _ms1;
    private var _hasPrev;
    private var _spd0;          // Doppler speed at the previous fix, m/s or null
    private var _spd1;
    private var _pending;       // [[gate, heading], ...] learned this lap, saved when it completes

    private var _trace;         // LapTrace of the lap in progress
    private var _splitTimes;    // cumulative split times in the lap in progress
    private var _autoPicked;    // nearest-track check done (or the user chose a track)
    private var _activity;      // ActivityRecording.Session or null
    private var _fit;           // RaceFit or null

    function initialize() {
        currentLocation = null;
        speed = null;
        heading = null;
        gpsQuality = Position.QUALITY_NOT_AVAILABLE;
        heartRate = null;
        maxHeartRate = null;
        hrZones = null;
        if (UserProfile has :getHeartRateZones) {
            try {
                hrZones = UserProfile.getHeartRateZones(UserProfile.HR_ZONE_SPORT_GENERIC);
            } catch (e) {
                hrZones = null;
            }
        }

        isRecording = false;
        sessionStartMs = null;
        sessionEndMs = null;
        _activity = null;
        _fit = null;
        _autoPicked = false;
        _hasPrev = false;
        clearTiming();
        loadConfig();
    }

    private function clearTiming() as Void {
        lapStartMs = null;
        laps = [];
        lapSectors = [];
        bestLapMs = null;
        bestSectors = null;
        lastDeltaMs = null;
        lastLapWasBest = false;
        lastLapWasRecord = false;
        lastLapCompletedMs = null;
        liveDeltaMs = null;
        liveProgress = null;
        lastSplitIndex = null;
        lastSplitDeltaMs = null;
        lastSplitMs = null;
        lastSplitAtMs = null;
        _trace = null;
        _splitTimes = [];
        _hasPrev = false;
        _pending = [];
    }

    function mode() as Number {
        return track.mode;
    }

    function isRunMode() as Boolean {
        return track.isRunMode();
    }

    // Time the current lap is compared with: the track record
    function referenceMs() {
        return record != null ? record.ms : null;
    }

    // Sum of this session's best sectors, or null
    function optimalMs() {
        var n = track.activeSplits().size();
        if (n == 0 || bestSectors == null || bestSectors.size() != n + 1) { return null; }
        return RaceMath.sum(bestSectors);
    }

    // ------------------------------------------------------------------
    // Tracks
    // ------------------------------------------------------------------

    function listTracks() as Array {
        return TrackStore.loadAll();
    }

    private function useTrack(t) as Void {
        track = t;
        record = TrackStore.loadRecord(t.id, t.mode);
        Application.Storage.setValue("currentTrack", t.id);
    }

    function selectTrack(id) as Boolean {
        if (isRecording) { return false; }
        if (id == track.id) { _autoPicked = true; return true; }   // keep the session's laps on screen
        var t = TrackStore.load(id);
        if (t == null) { return false; }
        _autoPicked = true;
        useTrack(t);
        clearTiming();
        sessionStartMs = null;
        return true;
    }

    function newTrack() as Boolean {
        if (isRecording || !TrackStore.canCreate()) { return false; }
        _autoPicked = true;
        useTrack(TrackStore.create(track.mode));
        clearTiming();
        sessionStartMs = null;
        return true;
    }

    function renameTrack(name) as Void {
        track.name = name;
        TrackStore.save(track);
    }

    function deleteTrack(id) as Boolean {
        if (isRecording) { return false; }
        var list = TrackStore.ids();
        if (list.size() <= 1) { return false; }
        TrackStore.remove(id);
        if (id == track.id) {
            var t = TrackStore.load(TrackStore.ids()[0]);
            if (t == null) { t = TrackStore.create(MODE_CIRCUIT); }
            useTrack(t);
            clearTiming();
            sessionStartMs = null;
        }
        return true;
    }

    // Saved track whose start line is nearest, within AUTO_TRACK_RADIUS_M
    private function nearestTrack(lat, lon) {
        var all = TrackStore.loadAll();
        var best = null;
        var bestD = AUTO_TRACK_RADIUS_M;
        for (var i = 0; i < all.size(); i++) {
            var g = all[i].startGate;
            if (g == null) { continue; }
            var d = g.distanceTo(lat, lon);
            if (d < bestD) {
                bestD = d;
                best = all[i];
            }
        }
        return best;
    }

    // ------------------------------------------------------------------
    // Track setup
    // ------------------------------------------------------------------

    function hasGpsFix() as Boolean {
        return currentLocation != null && gpsQuality != null
            && gpsQuality >= Position.QUALITY_USABLE;
    }

    private function gateHere() {
        if (!hasGpsFix()) {
            return null;
        }
        // Record direction of travel if we're moving, so wrong-way passes are ignored.
        // Otherwise it's learned the first time the line is crossed in a session.
        var h = null;
        if (speed != null && heading != null && speed >= MIN_HEADING_SPEED) {
            h = heading;
        }
        return TimingGate.fromLocation(currentLocation, h, GATE_RADIUS_M);
    }

    // Moving the start or finish line changes the lap, so old records no longer
    // apply. The finish line is only used by sprint and drag, so moving it
    // leaves circuit records alone.
    private function linesChanged(finishOnly as Boolean) as Number {
        TrackStore.save(track);
        var firstMode = finishOnly ? MODE_SPRINT : MODE_CIRCUIT;
        var had = TrackStore.hasRecords(track.id, firstMode);
        TrackStore.clearRecords(track.id, firstMode);
        record = TrackStore.loadRecord(track.id, track.mode);
        return had ? LINE_SET_RECORD_RESET : LINE_SET;
    }

    function setStartLine() as Number {
        var g = gateHere();
        if (g == null) { return LINE_FAILED; }
        track.startGate = g;
        return linesChanged(false);
    }

    function setFinishLine() as Number {
        var g = gateHere();
        if (g == null) { return LINE_FAILED; }
        track.finishGate = g;
        return linesChanged(true);
    }

    function canAddSplit() as Boolean {
        return track.usesSplits() && track.splits.size() < MAX_SPLITS;
    }

    function addSplit() as Boolean {
        if (!canAddSplit()) { return false; }
        var g = gateHere();
        if (g == null) { return false; }
        track.splits.add(g);
        splitsChanged();
        return true;
    }

    function clearSplits() as Void {
        track.splits = [];
        splitsChanged();
    }

    private function splitsChanged() as Void {
        TrackStore.save(track);
        TrackStore.clearSectorRecords(track.id);
        record = TrackStore.loadRecord(track.id, track.mode);
        bestSectors = null;
    }

    function clearLines() as Void {
        track.startGate = null;
        track.finishGate = null;
        track.splits = [];
        linesChanged(false);
    }

    function setMode(m as Number) as Void {
        if (isRecording || m == track.mode) { return; }
        track.mode = m;
        TrackStore.save(track);
        record = TrackStore.loadRecord(track.id, m);
        clearTiming();
        sessionStartMs = null;
    }

    // Returns a user-facing reason the session can't start, or null if ready.
    function startProblem() {
        if (track.startGate == null) {
            return isRunMode() ? "Set start line first" : "Set start/finish first";
        }
        if (isRunMode() && track.finishGate == null) {
            return "Set finish line first";
        }
        return null;
    }

    // ------------------------------------------------------------------
    // Session control
    // ------------------------------------------------------------------

    function startSession() as Void {
        clearTiming();
        maxHeartRate = heartRate;
        sessionStartMs = System.getTimer();
        sessionEndMs = null;
        isRecording = true;
        _autoPicked = true;     // don't switch tracks under a running session

        // Record a FIT activity so the session (GPS track, HR, laps) syncs to Garmin Connect.
        if (Toybox has :ActivityRecording) {
            try {
                _activity = ActivityRecording.createSession({
                    :name => ModeInfo.activityName(track.mode),
                    :sport => Activity.SPORT_DRIVING
                });
                if (Toybox has :FitContributor) {
                    try {
                        _fit = new RaceFit(_activity);
                    } catch (e) {
                        _fit = null;
                    }
                }
                _activity.start();
            } catch (e) {
                _activity = null;
                _fit = null;
            }
        }
    }

    function stopSession(save as Boolean) as Void {
        if (!isRecording) { return; }
        isRecording = false;
        sessionEndMs = System.getTimer();
        lapStartMs = null;
        liveDeltaMs = null;
        liveProgress = null;

        if (_activity != null) {
            if (_fit != null) {
                _fit.setSession(bestLapMs, optimalMs(), referenceMs());
            }
            if (_activity.isRecording()) {
                _activity.stop();
            }
            if (save) {
                _activity.save();
            } else {
                _activity.discard();
            }
            _activity = null;
            _fit = null;
        }
    }

    // ------------------------------------------------------------------
    // Sensor input
    // ------------------------------------------------------------------

    function onHeartRate(hr) as Void {
        heartRate = hr;
        if (isRecording && hr != null && (maxHeartRate == null || hr > maxHeartRate)) {
            maxHeartRate = hr;
        }
    }

    // Called for every GPS fix. Returns an EVENT_* code.
    function onPosition(info as Position.Info) as Number {
        var now = System.getTimer();
        gpsQuality = info.accuracy;
        speed = info.speed;
        heading = info.heading;

        var loc = info.position;
        if (loc == null) {
            return EVENT_NONE;
        }
        currentLocation = loc;

        // Only trust usable fixes for timing; a poor fix is skipped entirely so
        // the next segment is drawn from the last good point.
        if (gpsQuality == null || gpsQuality < Position.QUALITY_USABLE) {
            return EVENT_NONE;
        }

        var r = loc.toRadians();
        var lat = r[0].toDouble();
        var lon = r[1].toDouble();

        var evt = EVENT_NONE;

        // First good fix of the launch: switch to the saved track we're at.
        if (!_autoPicked && !isRecording) {
            _autoPicked = true;
            var near = nearestTrack(lat, lon);
            if (near != null && near.id != track.id) {
                useTrack(near);
                clearTiming();
                sessionStartMs = null;
                evt = EVENT_TRACK_CHANGED;
            }
        }

        if (isRecording && _hasPrev && (now - _ms1) <= MAX_FIX_GAP_MS) {
            _lat0 = _lat1; _lon0 = _lon1; _ms0 = _ms1; _spd0 = _spd1;
            _lat1 = lat;   _lon1 = lon;   _ms1 = now; _spd1 = speed;
            // A car that's parked or crawling never crosses a line: this keeps
            // GPS wander from triggering a start while you're staged on the line.
            if (speed == null || speed >= MIN_CROSS_SPEED) {
                evt = detectCrossing();
            }
        } else {
            _lat1 = lat; _lon1 = lon; _ms1 = now; _spd1 = speed;
        }
        _hasPrev = true;

        if (isRecording && lapStartMs != null) {
            trackLap(lat, lon, now);
        }
        return evt;
    }

    // Adds the fix to the lap trace and updates the live delta.
    private function trackLap(lat, lon, now) as Void {
        var p = track.startGate.toLocal(lat, lon);
        var el = now - lapStartMs;
        if (_trace != null) { _trace.add(p[0], p[1], el); }

        liveDeltaMs = null;
        liveProgress = null;
        if (record != null && record.trace != null && record.ms != null && record.ms > 0) {
            var refT = record.trace.timeAt(p[0], p[1], el);
            if (refT >= 0) {
                liveDeltaMs = el - refT;
                liveProgress = refT.toFloat() / record.ms;
            }
        }
        if (_fit != null) { _fit.setLiveDelta(liveDeltaMs); }
    }

    // Fraction (0..1) along the current segment where it crosses the gate, or -1
    private function crossFrac(gate) as Float {
        if (gate == null) { return -1.0; }
        return gate.crossingFraction(_lat0, _lon0, _lat1, _lon1);
    }

    private function segTime(t) as Number {
        return (_ms0 + t * (_ms1 - _ms0)).toNumber();
    }

    // Crossing point in the start line's frame, [x, y] metres
    private function segPoint(t) as Array {
        var lat = _lat0 + t * (_lat1 - _lat0);
        var lon = _lon0 + t * (_lon1 - _lon0);
        return track.startGate.toLocal(lat, lon);
    }

    private function detectCrossing() as Number {
        var m = track.mode;

        if (lapStartMs == null) {
            // Armed: waiting for the start line
            var ts = crossFrac(track.startGate);
            if (ts < 0) { return EVENT_NONE; }
            beginLap(startTime(ts), ts);
            learnDirection(track.startGate);
            // Close the out-lap (or the transit between runs) in the FIT file
            if (_activity != null && _activity.isRecording()) {
                if (_fit != null) { _fit.clearLap(); }
                _activity.addLap();
            }
            return EVENT_TIMING_STARTED;
        }

        var evt = checkSplit() ? EVENT_SPLIT : EVENT_NONE;

        var endGate = (m == MODE_CIRCUIT) ? track.startGate : track.finishGate;
        var te = crossFrac(endGate);
        if (te >= 0) {
            var at = segTime(te);
            var minMs = MIN_LAP_MS;
            if (m == MODE_SPRINT) { minMs = SPRINT_MIN_RUN_MS; }
            else if (m == MODE_DRAG) { minMs = DRAG_MIN_RUN_MS; }
            if (at - lapStartMs >= minMs) {
                learnDirection(endGate);
                completeLap(at, te);
                if (m == MODE_CIRCUIT) {
                    beginLap(at, te);
                } else {
                    lapStartMs = null;      // re-armed for the next run
                    _trace = null;
                    if (_fit != null) { _fit.setLiveDelta(null); }
                }
                return EVENT_LAP_COMPLETED;
            }
        }

        // Sprint/drag: crossing the start line again before any split (e.g.
        // driving back through it to stage) restarts the run from there.
        if (m != MODE_CIRCUIT && _splitTimes.size() == 0) {
            var tr = crossFrac(track.startGate);
            if (tr >= 0) {
                var atr = startTime(tr);
                if (atr - lapStartMs >= DRAG_MIN_RUN_MS) {
                    beginLap(atr, tr);
                    learnDirection(track.startGate);
                    return EVENT_TIMING_STARTED;
                }
            }
        }
        return evt;
    }

    // Start-line crossing time. In drag mode a launch from rest accelerates
    // through the segment, so distance grows with time squared: the line is
    // reached at sqrt(fraction) of the segment's time, not at the fraction.
    private function startTime(t) as Number {
        if (track.mode == MODE_DRAG && (_spd0 == null || _spd0 < MIN_CROSS_SPEED)) {
            return segTime(Math.sqrt(t));
        }
        return segTime(t);
    }

    // Checks the next split line in order. Returns true if it was crossed.
    private function checkSplit() as Boolean {
        var sp = track.activeSplits();
        var k = _splitTimes.size();
        if (k >= sp.size()) { return false; }
        var t = crossFrac(sp[k]);
        if (t < 0) { return false; }
        var since = segTime(t) - lapStartMs;
        var prev = (k > 0) ? _splitTimes[k - 1] : 0;
        if (since - prev < MIN_SPLIT_MS) { return false; }

        learnDirection(sp[k]);
        _splitTimes.add(since);
        lastSplitIndex = k + 1;
        lastSplitMs = since;
        lastSplitAtMs = System.getTimer();
        lastSplitDeltaMs = null;
        if (record != null && record.splits != null && record.splits.size() > k) {
            lastSplitDeltaMs = since - record.splits[k];
        }
        return true;
    }

    // A line set while standing still has no direction. Take it from the
    // crossings of the first lap or run that completes, so from then on
    // wrong-way passes are ignored. Nothing is kept from a run that never
    // finishes (or is restarted), so driving back through the start line to
    // stage can't teach it the wrong way.
    private function learnDirection(gate) as Void {
        if (gate == null || gate.heading != null) { return; }
        for (var i = 0; i < _pending.size(); i++) {
            if (_pending[i][0] == gate) { return; }
        }
        var h = gate.headingOf(_lat0, _lon0, _lat1, _lon1, _ms1 - _ms0, MIN_HEADING_SPEED);
        if (h != null) { _pending.add([gate, h]); }
    }

    private function commitDirections() as Void {
        var changed = false;
        for (var i = 0; i < _pending.size(); i++) {
            var g = _pending[i][0];
            if (g.heading == null) {
                g.heading = _pending[i][1];
                changed = true;
            }
        }
        _pending = [];
        if (changed) { TrackStore.save(track); }
    }

    private function beginLap(at as Number, t) as Void {
        lapStartMs = at;
        _pending = [];
        _splitTimes = [];
        lastSplitIndex = null;
        liveDeltaMs = null;
        liveProgress = null;
        _trace = new LapTrace(null);
        var p = segPoint(t);
        _trace.add(p[0], p[1], 0);
        if (record != null && record.trace != null) { record.trace.resetCursor(); }
    }

    private function completeLap(at as Number, t) as Void {
        commitDirections();
        var lap = at - lapStartMs;
        if (_trace != null) {
            var p = segPoint(t);
            _trace.add(p[0], p[1], lap);
        }

        // Sector times, if every split was crossed
        var sectors = null;
        var n = track.activeSplits().size();
        if (n > 0 && _splitTimes.size() == n) {
            sectors = [];
            var prev = 0;
            for (var i = 0; i < n; i++) {
                sectors.add(_splitTimes[i] - prev);
                prev = _splitTimes[i];
            }
            sectors.add(lap - prev);
            bestSectors = RaceMath.minEach(bestSectors, sectors);
        }

        var prevRecord = referenceMs();
        lastDeltaMs = (prevRecord != null) ? lap - prevRecord : null;
        lastLapWasRecord = (prevRecord == null || lap < prevRecord);
        lastLapWasBest = (bestLapMs == null || lap < bestLapMs);
        if (lastLapWasBest) {
            bestLapMs = lap;
        }
        laps.add(lap);
        lapSectors.add(sectors);
        lastLapCompletedMs = System.getTimer();
        liveDeltaMs = null;
        liveProgress = null;

        updateRecord(lap, sectors);

        if (_activity != null && _activity.isRecording()) {
            if (_fit != null) { _fit.setLap(lap, lastDeltaMs, sectors); }
            _activity.addLap();
            if (_fit != null) { _fit.clearLap(); }
        }
    }

    private function updateRecord(lap as Number, sectors) as Void {
        var changed = false;
        if (record == null) { record = new TrackRecord(); }
        if (lastLapWasRecord) {
            record.ms = lap;
            record.trace = _trace;
            record.splits = (sectors != null) ? _splitTimes : null;
            changed = true;
        }
        if (sectors != null) {
            var merged = RaceMath.minEach(record.sectors, sectors);
            if (!RaceMath.sameArray(merged, record.sectors)) {
                record.sectors = merged;
                changed = true;
            }
        }
        if (changed) {
            TrackStore.saveRecord(track.id, track.mode, record);
        }
    }

    // ------------------------------------------------------------------
    // Read-outs
    // ------------------------------------------------------------------

    function getCurrentLapMs() {
        if (isRecording && lapStartMs != null) {
            return System.getTimer() - lapStartMs;
        }
        return null;
    }

    function getSessionMs() {
        if (sessionStartMs == null) { return null; }
        var end = isRecording ? System.getTimer() : sessionEndMs;
        return end - sessionStartMs;
    }

    // 0 = resting, 1..5 = HR zone of the current heart rate; null if unknown
    function getHeartRateZone() {
        if (heartRate == null || hrZones == null || hrZones.size() < 6) { return null; }
        var zones = hrZones as Array<Number>;
        if (heartRate < zones[0]) { return 0; }
        for (var z = 1; z < 5; z++) {
            if (heartRate < zones[z]) { return z; }
        }
        return 5;
    }

    // How far through the lap we are compared with the record lap (can exceed
    // 1.0), or null. Uses position on track when the record trace matches,
    // otherwise elapsed time.
    function getLapProgress() {
        if (liveProgress != null) { return liveProgress; }
        var cur = getCurrentLapMs();
        var ref = referenceMs();
        if (cur == null || ref == null || ref <= 0) { return null; }
        return cur.toFloat() / ref;
    }

    function getLastLapMs() {
        var l = laps as Array<Number>;
        return l.size() > 0 ? l[l.size() - 1] : null;
    }

    function getBestLapNumber() {
        if (bestLapMs == null) { return null; }
        var l = laps as Array<Number>;
        for (var i = 0; i < l.size(); i++) {
            if (l[i] == bestLapMs) { return i + 1; }
        }
        return null;
    }

    // ------------------------------------------------------------------
    // Persistence
    // ------------------------------------------------------------------

    private function loadConfig() as Void {
        var t = null;
        try {
            TrackStore.migrateLegacy();
            t = TrackStore.load(Application.Storage.getValue("currentTrack"));
            if (t == null) {
                var list = TrackStore.ids();
                if (list.size() > 0) { t = TrackStore.load(list[0]); }
            }
            if (t == null) { t = TrackStore.create(MODE_CIRCUIT); }
            useTrack(t);
        } catch (e) {
            // Storage unreadable: run with an unsaved track rather than not at all.
            track = (t != null) ? t : new Track(1, "Track 1");
            record = null;
        }
    }
}
