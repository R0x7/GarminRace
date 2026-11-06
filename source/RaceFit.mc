import Toybox.ActivityRecording;
import Toybox.FitContributor;
import Toybox.Lang;

// Field ids: must match resources/fit/fitcontributions.xml
const FIT_LIVE_DELTA = 0;
const FIT_LAP_TIME = 1;
const FIT_LAP_DELTA = 2;
const FIT_SECTOR_1 = 3;      // 3, 4, 5
const FIT_BEST_LAP = 6;
const FIT_OPTIMAL_LAP = 7;
const FIT_TRACK_RECORD = 8;

// Custom data written into the FIT activity so Garmin Connect shows the
// timer's own numbers: the GPS-interpolated lap time, gap to the track record,
// sector times, and a live-delta chart. All times are in seconds.
//
// Lap fields are zero on laps that weren't timed (the out-lap, and the
// transit between sprint/drag runs), and sector fields are zero when a split
// was missed.
class RaceFit {
    private var _liveDelta;
    private var _lapTime;
    private var _lapDelta;
    private var _sectors as Array = [];
    private var _best;
    private var _optimal;
    private var _record;

    function initialize(session as ActivityRecording.Session) {
        var f = FitContributor.DATA_TYPE_FLOAT;
        _liveDelta = session.createField("live_delta", FIT_LIVE_DELTA, f,
            {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "s"});
        _lapTime = session.createField("lap_time", FIT_LAP_TIME, f,
            {:mesgType => FitContributor.MESG_TYPE_LAP, :units => "s"});
        _lapDelta = session.createField("gap_to_record", FIT_LAP_DELTA, f,
            {:mesgType => FitContributor.MESG_TYPE_LAP, :units => "s"});
        for (var i = 0; i < 3; i++) {
            _sectors.add(session.createField("sector_" + (i + 1).toString(), FIT_SECTOR_1 + i, f,
                {:mesgType => FitContributor.MESG_TYPE_LAP, :units => "s"}));
        }
        _best = session.createField("best_lap", FIT_BEST_LAP, f,
            {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "s"});
        _optimal = session.createField("optimal_lap", FIT_OPTIMAL_LAP, f,
            {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "s"});
        _record = session.createField("track_record", FIT_TRACK_RECORD, f,
            {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "s"});

        _liveDelta.setData(0.0);
        clearLap();
        setSession(null, null, null);
    }

    function setLiveDelta(ms) as Void {
        _liveDelta.setData(secs(ms));
    }

    // Values for the lap about to be closed with Session.addLap()
    function setLap(lapMs, gapMs, sectors) as Void {
        _lapTime.setData(secs(lapMs));
        _lapDelta.setData(secs(gapMs));
        for (var i = 0; i < _sectors.size(); i++) {
            var v = (sectors != null && i < sectors.size()) ? sectors[i] : null;
            _sectors[i].setData(secs(v));
        }
    }

    // Zero the lap fields so the next (possibly untimed) lap doesn't repeat them
    function clearLap() as Void {
        setLap(null, null, null);
    }

    function setSession(bestMs, optimalMs, recordMs) as Void {
        _best.setData(secs(bestMs));
        _optimal.setData(secs(optimalMs));
        _record.setData(secs(recordMs));
    }

    private function secs(ms) as Float {
        return ms != null ? ms.toFloat() / 1000.0 : 0.0;
    }
}
