import Toybox.Lang;
import Toybox.WatchUi;

// Main menu, rebuilt each time it opens so labels reflect the current state.
module RaceMenu {

    function gateStatus(gate) as String {
        if (gate == null) { return "Not set"; }
        return gate.isDirectional() ? "Set (with direction)" : "Set";
    }

    function open(transition) as Void {
        var s = getApp().raceSession;
        var menu = new WatchUi.Menu2({:title => "Race"});

        if (s.isRecording) {
            menu.addItem(new WatchUi.MenuItem("Stop & Save", s.laps.size().toString() + " laps", :stop_save, null));
            menu.addItem(new WatchUi.MenuItem("Discard Session", null, :discard, null));
        } else {
            menu.addItem(new WatchUi.MenuItem("Start Session",
                s.isPointToPoint ? "Sprint (A to B)" : "Circuit laps", :start, null));
        }

        if (s.isPointToPoint) {
            menu.addItem(new WatchUi.MenuItem("Set Start Line", gateStatus(s.startGate), :set_start, null));
            menu.addItem(new WatchUi.MenuItem("Set Finish Line", gateStatus(s.finishGate), :set_finish, null));
        } else {
            menu.addItem(new WatchUi.MenuItem("Set Start/Finish", gateStatus(s.startGate), :set_start, null));
        }

        menu.addItem(new WatchUi.ToggleMenuItem("Sprint Mode",
            {:enabled => "A to B runs", :disabled => "Off (circuit laps)"},
            :toggle_p2p, s.isPointToPoint, null));

        if (s.laps.size() > 0) {
            menu.addItem(new WatchUi.MenuItem(s.isPointToPoint ? "Run History" : "Lap History",
                "Best " + TimeFormat.lap(s.bestLapMs), :history, null));
        }

        if (s.startGate != null || s.finishGate != null) {
            menu.addItem(new WatchUi.MenuItem("Clear Lines", null, :clear_lines, null));
        }

        WatchUi.pushView(menu, new RaceMenuDelegate(), transition);
    }

}

class RaceMenuDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        var s = getApp().raceSession;

        if (id == :start) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            RaceActions.startSession();

        } else if (id == :stop_save) {
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
            RaceActions.confirm("Stop and save session?", ACTION_STOP_SAVE);

        } else if (id == :discard) {
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
            RaceActions.confirm("Discard this session?", ACTION_DISCARD);

        } else if (id == :set_start || id == :set_finish) {
            var ok = (id == :set_start) ? s.setStartLine() : s.setFinishLine();
            if (ok) {
                RaceAlerts.confirm();
                WatchUi.popView(WatchUi.SLIDE_DOWN);
                var name = (id == :set_finish) ? "Finish" : (s.isPointToPoint ? "Start" : "Start/finish");
                RaceAlerts.toast(name + " line set");
            } else {
                RaceAlerts.error();
                RaceAlerts.toast("Waiting for GPS fix");
            }

        } else if (id == :toggle_p2p) {
            if (s.isRecording) {
                (item as WatchUi.ToggleMenuItem).setEnabled(s.isPointToPoint);   // undo the toggle
                RaceAlerts.toast("Stop session first");
                return;
            }
            s.setPointToPoint(!s.isPointToPoint);
            // Rebuild so the line items match the new mode.
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
            RaceMenu.open(WatchUi.SLIDE_IMMEDIATE);

        } else if (id == :history) {
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
            var view = new LapHistoryView();
            WatchUi.pushView(view, new LapHistoryDelegate(view), WatchUi.SLIDE_UP);

        } else if (id == :clear_lines) {
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
            RaceActions.confirm("Clear timing lines?", ACTION_CLEAR_LINES);
        }
    }
}
