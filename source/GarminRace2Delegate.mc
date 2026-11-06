import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

const ACTION_STOP_SAVE = 1;
const ACTION_STOP_SAVE_EXIT = 2;
const ACTION_DISCARD = 3;
const ACTION_CLEAR_LINES = 4;

// Button handling on the main screen:
//   START (top button)  - start session / stop & save (with confirmation)
//   BACK                - exit (asks to save first if a session is running)
//   MENU (hold)         - track setup and session menu
//   Swipe up / DOWN     - lap history page
// Screen taps are deliberately ignored so a bumped wrist in the car can't
// stop a session.
class GarminRace2Delegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onKey(evt as KeyEvent) as Boolean {
        if (evt.getKey() == WatchUi.KEY_ENTER) {
            RaceActions.toggleSession();
            return true;
        }
        return BehaviorDelegate.onKey(evt);
    }

    function onMenu() as Boolean {
        RaceMenu.open(WatchUi.SLIDE_UP);
        return true;
    }

    function onNextPage() as Boolean {
        var view = new LapHistoryView();
        WatchUi.pushView(view, new LapHistoryDelegate(view), WatchUi.SLIDE_UP);
        return true;
    }

    function onBack() as Boolean {
        if (getApp().raceSession.isRecording) {
            RaceActions.confirm("Save session and exit?", ACTION_STOP_SAVE_EXIT);
            return true;
        }
        return false;   // let the system exit the app
    }
}

module RaceActions {

    function toggleSession() as Void {
        if (getApp().raceSession.isRecording) {
            confirm("Stop and save session?", ACTION_STOP_SAVE);
        } else {
            startSession();
        }
    }

    function startSession() as Void {
        var s = getApp().raceSession;
        var problem = s.startProblem();
        if (problem != null) {
            RaceAlerts.error();
            RaceAlerts.toast(problem);
            return;
        }
        s.startSession();
        RaceAlerts.confirm();
        RaceAlerts.toast(s.isPointToPoint ? "Armed - cross start" : "Armed - cross line");
        WatchUi.requestUpdate();
    }

    function confirm(message as String, action as Number) as Void {
        WatchUi.pushView(new WatchUi.Confirmation(message), new ConfirmActionDelegate(action), WatchUi.SLIDE_IMMEDIATE);
    }
}

class ConfirmActionDelegate extends WatchUi.ConfirmationDelegate {
    private var _action as Number;

    function initialize(action as Number) {
        ConfirmationDelegate.initialize();
        _action = action;
    }

    function onResponse(response as WatchUi.Confirm) as Boolean {
        if (response != WatchUi.CONFIRM_YES) {
            return true;
        }
        var s = getApp().raceSession;
        if (_action == ACTION_STOP_SAVE || _action == ACTION_STOP_SAVE_EXIT) {
            s.stopSession(true);
            RaceAlerts.confirm();
            RaceAlerts.toast("Session saved");
            if (_action == ACTION_STOP_SAVE_EXIT) {
                System.exit();
            }
        } else if (_action == ACTION_DISCARD) {
            s.stopSession(false);
            RaceAlerts.toast("Session discarded");
        } else if (_action == ACTION_CLEAR_LINES) {
            s.clearLines();
            RaceAlerts.toast("Lines cleared");
        }
        WatchUi.requestUpdate();
        return true;
    }
}
