import Toybox.Lang;
import Toybox.WatchUi;

const MAX_NAME_LEN = 16;

// Menus, rebuilt each time they open so labels reflect the current state.
//
//   Race                     main menu
//     Track  ->  tracks      pick, add, rename or delete saved tracks
//     Mode   ->  modes       Circuit / Sprint / Drag
//     lines, splits, history, clear
module RaceMenu {

    function gateStatus(gate) as String {
        if (gate == null) { return "Not set"; }
        return gate.isDirectional() ? "Set (with direction)" : "Set (direction on 1st pass)";
    }

    function open(transition) as Void {
        var s = getApp().raceSession;
        var t = s.track;
        var unit = s.isRunMode() ? "runs" : "laps";
        var menu = new WatchUi.Menu2({:title => "Race"});

        if (s.isRecording) {
            menu.addItem(new WatchUi.MenuItem("Stop & Save", s.laps.size().toString() + " " + unit, :stop_save, null));
            menu.addItem(new WatchUi.MenuItem("Discard Session", null, :discard, null));
        } else {
            menu.addItem(new WatchUi.MenuItem("Start Session",
                ModeInfo.name(t.mode) + ": " + ModeInfo.description(t.mode), :start, null));
        }

        var rec = s.referenceMs();
        menu.addItem(new WatchUi.MenuItem("Track",
            t.name + (rec != null ? "  ·  " + TimeFormat.lap(rec) : ""), :track, null));
        menu.addItem(new WatchUi.MenuItem("Mode", ModeInfo.name(t.mode), :mode, null));

        if (s.isRunMode()) {
            menu.addItem(new WatchUi.MenuItem("Set Start Line", gateStatus(t.startGate), :set_start, null));
            menu.addItem(new WatchUi.MenuItem("Set Finish Line", gateStatus(t.finishGate), :set_finish, null));
        } else {
            menu.addItem(new WatchUi.MenuItem("Set Start/Finish", gateStatus(t.startGate), :set_start, null));
        }

        if (t.usesSplits()) {
            if (s.canAddSplit()) {
                menu.addItem(new WatchUi.MenuItem("Add Split Here",
                    "Split " + (t.splits.size() + 1).toString() + " of " + MAX_SPLITS.toString(), :add_split, null));
            }
            if (t.splits.size() > 0) {
                menu.addItem(new WatchUi.MenuItem("Clear Splits",
                    t.splits.size().toString() + " set", :clear_splits, null));
            }
        }

        if (s.laps.size() > 0) {
            menu.addItem(new WatchUi.MenuItem(s.isRunMode() ? "Run History" : "Lap History",
                "Best " + TimeFormat.lap(s.bestLapMs), :history, null));
        }

        if (t.hasAnyLine()) {
            menu.addItem(new WatchUi.MenuItem("Clear Lines", null, :clear_lines, null));
        }

        WatchUi.pushView(menu, new RaceMenuDelegate(), transition);
    }

    function openModes() as Void {
        var s = getApp().raceSession;
        var menu = new WatchUi.Menu2({:title => "Mode"});
        for (var m = 0; m < MODE_COUNT; m++) {
            var label = ModeInfo.name(m);
            if (m == s.mode()) { label = "> " + label; }
            menu.addItem(new WatchUi.MenuItem(label, ModeInfo.description(m), m, null));
        }
        WatchUi.pushView(menu, new ModeMenuDelegate(), WatchUi.SLIDE_LEFT);
    }

    function openTracks() as Void {
        var s = getApp().raceSession;
        var menu = new WatchUi.Menu2({:title => "Tracks"});
        var all = s.listTracks();
        for (var i = 0; i < all.size(); i++) {
            var t = all[i];
            var label = t.name;
            if (t.id == s.track.id) { label = "> " + label; }
            var sub = ModeInfo.name(t.mode) + (t.startGate == null ? "  ·  no lines" : "");
            menu.addItem(new WatchUi.MenuItem(label, sub, t.id, null));
        }
        if (TrackStore.canCreate()) {
            menu.addItem(new WatchUi.MenuItem("New Track", null, :new_track, null));
        }
        if (WatchUi has :TextPicker) {
            menu.addItem(new WatchUi.MenuItem("Rename Track", s.track.name, :rename_track, null));
        }
        if (all.size() > 1) {
            menu.addItem(new WatchUi.MenuItem("Delete Track", s.track.name, :delete_track, null));
        }
        WatchUi.pushView(menu, new TrackMenuDelegate(), WatchUi.SLIDE_LEFT);
    }

    // Close a submenu and the main menu under it, then reopen the main menu
    // so its labels are up to date.
    function refreshFromSubmenu() as Void {
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        open(WatchUi.SLIDE_IMMEDIATE);
    }

    // Close a submenu and the main menu, back to the race screen
    function closeAll() as Void {
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
    }

    function blockedWhileRecording() as Boolean {
        if (getApp().raceSession.isRecording) {
            RaceAlerts.error();
            RaceAlerts.toast("Stop session first");
            return true;
        }
        return false;
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

        } else if (id == :track) {
            if (RaceMenu.blockedWhileRecording()) { return; }
            RaceMenu.openTracks();

        } else if (id == :mode) {
            if (RaceMenu.blockedWhileRecording()) { return; }
            RaceMenu.openModes();

        } else if (id == :set_start || id == :set_finish) {
            if (RaceMenu.blockedWhileRecording()) { return; }
            var res = (id == :set_start) ? s.setStartLine() : s.setFinishLine();
            if (res == LINE_FAILED) {
                RaceAlerts.error();
                RaceAlerts.toast("Waiting for GPS fix");
                return;
            }
            RaceAlerts.confirm();
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            var name = (id == :set_finish) ? "Finish" : (s.isRunMode() ? "Start" : "Start/finish");
            RaceAlerts.toast(res == LINE_SET_RECORD_RESET ? name + " set, records reset" : name + " line set");

        } else if (id == :add_split) {
            if (RaceMenu.blockedWhileRecording()) { return; }
            if (s.addSplit()) {
                RaceAlerts.confirm();
                WatchUi.popView(WatchUi.SLIDE_DOWN);
                RaceAlerts.toast("Split " + s.track.splits.size().toString() + " set");
            } else {
                RaceAlerts.error();
                RaceAlerts.toast("Waiting for GPS fix");
            }

        } else if (id == :clear_splits) {
            if (RaceMenu.blockedWhileRecording()) { return; }
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
            RaceActions.confirm("Clear split lines?", ACTION_CLEAR_SPLITS);

        } else if (id == :history) {
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
            var view = new LapHistoryView();
            WatchUi.pushView(view, new LapHistoryDelegate(view), WatchUi.SLIDE_UP);

        } else if (id == :clear_lines) {
            if (RaceMenu.blockedWhileRecording()) { return; }
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
            RaceActions.confirm("Clear lines and records?", ACTION_CLEAR_LINES);
        }
    }
}

class ModeMenuDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var m = item.getId() as Number;
        getApp().raceSession.setMode(m);
        RaceAlerts.confirm();
        RaceMenu.refreshFromSubmenu();
    }
}

class TrackMenuDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        var s = getApp().raceSession;

        if (id == :new_track) {
            if (s.newTrack()) {
                RaceAlerts.confirm();
                RaceMenu.refreshFromSubmenu();
                RaceAlerts.toast(s.track.name + " created");
            } else {
                RaceAlerts.error();
            }

        } else if (id == :rename_track) {
            RaceMenu.closeAll();
            WatchUi.pushView(new WatchUi.TextPicker(s.track.name), new RenameTrackDelegate(), WatchUi.SLIDE_IMMEDIATE);

        } else if (id == :delete_track) {
            RaceMenu.closeAll();
            RaceActions.confirmWith("Delete " + s.track.name + " and its records?", ACTION_DELETE_TRACK, s.track.id);

        } else if (id instanceof Number) {
            if (s.selectTrack(id)) {
                RaceAlerts.confirm();
                RaceMenu.refreshFromSubmenu();
            } else {
                RaceAlerts.error();
            }
        }
    }
}

class RenameTrackDelegate extends WatchUi.TextPickerDelegate {

    function initialize() {
        TextPickerDelegate.initialize();
    }

    function onTextEntered(text as String, changed as Boolean) as Boolean {
        if (text.length() > 0) {
            var name = text;
            if (text.length() > MAX_NAME_LEN) { name = text.substring(0, MAX_NAME_LEN); }
            getApp().raceSession.renameTrack(name);
            RaceAlerts.toast("Renamed");
        }
        WatchUi.requestUpdate();
        return true;
    }

    function onCancel() as Boolean {
        return true;
    }
}
