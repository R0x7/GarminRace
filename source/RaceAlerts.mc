import Toybox.Attention;
import Toybox.Lang;
import Toybox.WatchUi;

// On-watch feedback: vibration, tones and toast messages.
module RaceAlerts {

    function vibrate(pattern as Array) as Void {
        if (Attention has :vibrate) {
            Attention.vibrate(pattern);
        }
    }

    function tone(t) as Void {
        if (Attention has :playTone) {
            Attention.playTone(t);
        }
    }

    function toast(message as String) as Void {
        if (WatchUi has :showToast) {
            WatchUi.showToast(message, null);
        }
    }

    // Short buzz: action accepted
    function confirm() as Void {
        vibrate([new Attention.VibeProfile(60, 120)]);
    }

    // Double buzz: something went wrong
    function error() as Void {
        vibrate([new Attention.VibeProfile(80, 150),
                 new Attention.VibeProfile(0, 100),
                 new Attention.VibeProfile(80, 150)]);
    }

    function timingStarted() as Void {
        vibrate([new Attention.VibeProfile(100, 250)]);
        tone(Attention.TONE_START);
    }

    // Long buzz for a lap; triple buzz for a new best
    function lap(isBest as Boolean) as Void {
        if (isBest) {
            vibrate([new Attention.VibeProfile(100, 200),
                     new Attention.VibeProfile(0, 100),
                     new Attention.VibeProfile(100, 200),
                     new Attention.VibeProfile(0, 100),
                     new Attention.VibeProfile(100, 200)]);
        } else {
            vibrate([new Attention.VibeProfile(100, 500)]);
        }
        tone(Attention.TONE_LAP);
    }
}
