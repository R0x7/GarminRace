import Toybox.Activity;
import Toybox.ActivityRecording;
import Toybox.Application;
import Toybox.Lang;
import Toybox.Position;
import Toybox.System;
import Toybox.UserProfile;

const GATE_RADIUS_M = 25.0;      // capture radius around a timing line point
const MIN_LAP_MS = 10000;        // ignore crossings closer together than this
const MIN_HEADING_SPEED = 3.0;   // m/s; below this GPS heading is unreliable
const MAX_FIX_GAP_MS = 4000;     // don't interpolate a crossing across a GPS dropout longer than this

const EVENT_NONE = 0;
const EVENT_TIMING_STARTED = 1;
const EVENT_LAP_COMPLETED = 2;

// Holds track setup, live sensor data and lap timing.
// All timing uses System.getTimer() (milliseconds) for sub-second precision.
class RaceSessionModel {
    // --- Track setup (persisted between launches) ---
    var startGate;          // TimingGate or null (start/finish line in circuit mode)
    var finishGate;         // TimingGate or null (sprint mode only)
    var isPointToPoint;     // false = circuit laps, true = A-to-B sprint runs

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
    var bestLapMs;
    var lastDeltaMs;        // last lap minus the previous best (negative = faster)
    var lastLapWasBest;
    var lastLapCompletedMs;

    private var _prevLat;
    private var _prevLon;
    private var _prevMs;
    private var _lastCrossMs;
    private var _activity;  // ActivityRecording.Session or null

    function initialize() {
        startGate = null;
        finishGate = null;
        isPointToPoint = false;

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
        clearTiming();
        loadConfig();
    }

    private function clearTiming() as Void {
        lapStartMs = null;
        laps = [];
        bestLapMs = null;
        lastDeltaMs = null;
        lastLapWasBest = false;
        lastLapCompletedMs = null;
        _lastCrossMs = null;
        _prevMs = null;
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
        var h = null;
        if (speed != null && heading != null && speed >= MIN_HEADING_SPEED) {
            h = heading;
        }
        return TimingGate.fromLocation(currentLocation, h, GATE_RADIUS_M);
    }

    function setStartLine() as Boolean {
        var g = gateHere();
        if (g == null) { return false; }
        startGate = g;
        saveConfig();
        return true;
    }

    function setFinishLine() as Boolean {
        var g = gateHere();
        if (g == null) { return false; }
        finishGate = g;
        saveConfig();
        return true;
    }

    function clearLines() as Void {
        startGate = null;
        finishGate = null;
        saveConfig();
    }

    function setPointToPoint(enabled as Boolean) as Void {
        isPointToPoint = enabled;
        saveConfig();
    }

    // Returns a user-facing reason the session can't start, or null if ready.
    function startProblem() {
        if (startGate == null) {
            return isPointToPoint ? "Set start line first" : "Set start/finish first";
        }
        if (isPointToPoint && finishGate == null) {
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

        // Record a FIT activity so the session (GPS track, HR, laps) syncs to Garmin Connect.
        if (Toybox has :ActivityRecording) {
            try {
                _activity = ActivityRecording.createSession({
                    :name => isPointToPoint ? "Sprint" : "Track Day",
                    :sport => Activity.SPORT_DRIVING
                });
                _activity.start();
            } catch (e) {
                _activity = null;
            }
        }
    }

    function stopSession(save as Boolean) as Void {
        if (!isRecording) { return; }
        isRecording = false;
        sessionEndMs = System.getTimer();
        lapStartMs = null;

        if (_activity != null) {
            if (_activity.isRecording()) {
                _activity.stop();
            }
            if (save) {
                _activity.save();
            } else {
                _activity.discard();
            }
            _activity = null;
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
        if (isRecording && _prevMs != null && (now - _prevMs) <= MAX_FIX_GAP_MS) {
            evt = detectCrossing(_prevLat, _prevLon, _prevMs, lat, lon, now);
        }
        _prevLat = lat;
        _prevLon = lon;
        _prevMs = now;
        return evt;
    }

    // Interpolated crossing time in ms, or -1 if the gate wasn't crossed.
    private function crossTime(gate, lat0, lon0, ms0, lat1, lon1, ms1) as Number {
        if (gate == null) { return -1; }
        var t = gate.crossingFraction(lat0, lon0, lat1, lon1);
        if (t < 0) { return -1; }
        return (ms0 + t * (ms1 - ms0)).toNumber();
    }

    private function detectCrossing(lat0, lon0, ms0, lat1, lon1, ms1) as Number {
        if (isPointToPoint) {
            if (lapStartMs == null) {
                var atStart = crossTime(startGate, lat0, lon0, ms0, lat1, lon1, ms1);
                if (atStart >= 0 && debounced(atStart)) {
                    lapStartMs = atStart;
                    return EVENT_TIMING_STARTED;
                }
            } else {
                var atFinish = crossTime(finishGate, lat0, lon0, ms0, lat1, lon1, ms1);
                if (atFinish >= 0 && debounced(atFinish)) {
                    completeLap(atFinish);
                    lapStartMs = null;      // re-armed for the next run
                    return EVENT_LAP_COMPLETED;
                }
            }
        } else {
            var atLine = crossTime(startGate, lat0, lon0, ms0, lat1, lon1, ms1);
            if (atLine >= 0 && debounced(atLine)) {
                if (lapStartMs == null) {   // first crossing ends the out-lap
                    lapStartMs = atLine;
                    return EVENT_TIMING_STARTED;
                }
                completeLap(atLine);
                lapStartMs = atLine;
                return EVENT_LAP_COMPLETED;
            }
        }
        return EVENT_NONE;
    }

    private function debounced(at as Number) as Boolean {
        if (_lastCrossMs != null && (at - _lastCrossMs) < MIN_LAP_MS) {
            return false;
        }
        _lastCrossMs = at;
        return true;
    }

    private function completeLap(at as Number) as Void {
        var lap = at - lapStartMs;
        lastDeltaMs = (bestLapMs != null) ? lap - bestLapMs : null;
        lastLapWasBest = (bestLapMs == null || lap < bestLapMs);
        if (lastLapWasBest) {
            bestLapMs = lap;
        }
        laps.add(lap);
        lastLapCompletedMs = System.getTimer();

        if (_activity != null && _activity.isRecording()) {
            _activity.addLap();
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

    // Fraction of the best lap elapsed in the current lap (can exceed 1.0), or null
    function getLapProgress() {
        var cur = getCurrentLapMs();
        if (cur == null || bestLapMs == null || bestLapMs <= 0) { return null; }
        return cur.toFloat() / bestLapMs;
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
        try {
            startGate = TimingGate.fromStorage(Application.Storage.getValue("startGate"), GATE_RADIUS_M);
            finishGate = TimingGate.fromStorage(Application.Storage.getValue("finishGate"), GATE_RADIUS_M);
            isPointToPoint = (Application.Storage.getValue("pointToPoint") == true);
        } catch (e) {
            startGate = null;
            finishGate = null;
            isPointToPoint = false;
        }
    }

    private function saveConfig() as Void {
        storeGate("startGate", startGate);
        storeGate("finishGate", finishGate);
        Application.Storage.setValue("pointToPoint", isPointToPoint);
    }

    private function storeGate(key as String, gate) as Void {
        if (gate != null) {
            Application.Storage.setValue(key, gate.toStorage());
        } else {
            Application.Storage.deleteValue(key);
        }
    }
}
