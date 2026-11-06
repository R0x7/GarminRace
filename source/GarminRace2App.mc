import Toybox.Activity;
import Toybox.Application;
import Toybox.Lang;
import Toybox.Position;
import Toybox.Sensor;
import Toybox.WatchUi;

class GarminRace2App extends Application.AppBase {
    var raceSession as RaceSessionModel;

    function initialize() {
        AppBase.initialize();
        raceSession = new RaceSessionModel();
    }

    function onStart(state as Dictionary?) as Void {
        enablePositioning();

        // Heart rate: wrist sensor plus any paired chest strap.
        Sensor.setEnabledSensors([Sensor.SENSOR_HEARTRATE]);
        Sensor.enableSensorEvents(method(:onSensor));
    }

    function onStop(state as Dictionary?) as Void {
        // Never lose a recording if the app is closed mid-session.
        raceSession.stopSession(true);
        Position.enableLocationEvents(Position.LOCATION_DISABLE, null);
        Sensor.enableSensorEvents(null);
    }

    private function enablePositioning() as Void {
        var cb = method(:onPosition);
        var opts = {:acquisitionType => Position.LOCATION_CONTINUOUS};
        // Multi-band / multi-constellation gives better accuracy where supported.
        if (Position has :hasConfigurationSupport) {
            if ((Position has :CONFIGURATION_GPS_GALILEO_L1_L5)
                && Position.hasConfigurationSupport(Position.CONFIGURATION_GPS_GALILEO_L1_L5)) {
                opts[:configuration] = Position.CONFIGURATION_GPS_GALILEO_L1_L5;
            } else if ((Position has :CONFIGURATION_GPS_GALILEO)
                && Position.hasConfigurationSupport(Position.CONFIGURATION_GPS_GALILEO)) {
                opts[:configuration] = Position.CONFIGURATION_GPS_GALILEO;
            }
        }
        try {
            Position.enableLocationEvents(opts, cb);
        } catch (e) {
            Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, cb);
        }
    }

    function onPosition(info as Position.Info) as Void {
        var evt = raceSession.onPosition(info);
        if (evt == EVENT_LAP_COMPLETED) {
            RaceAlerts.lap(raceSession.lastLapWasBest);
        } else if (evt == EVENT_TIMING_STARTED) {
            RaceAlerts.timingStarted();
        }
        WatchUi.requestUpdate();
    }

    function onSensor(info as Sensor.Info) as Void {
        var hr = info.heartRate;
        if (hr == null) {
            // Fall back to the value the activity recorder sees (e.g. a paired strap).
            var act = Activity.getActivityInfo();
            if (act != null) { hr = act.currentHeartRate; }
        }
        raceSession.onHeartRate(hr);
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        return [ new GarminRace2View(), new GarminRace2Delegate() ];
    }
}

function getApp() as GarminRace2App {
    return Application.getApp() as GarminRace2App;
}
