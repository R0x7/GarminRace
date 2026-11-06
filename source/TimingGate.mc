import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;

const EARTH_RADIUS_M = 6371000.0d;

// A timing line, stored as a point plus a capture radius (and, optionally,
// the direction of travel when it was set).
//
// A crossing is detected when the straight segment between two consecutive
// GPS fixes passes within `radius` metres of the point. The crossing moment
// is interpolated along that segment, which gives sub-second timing and means
// a fast car can't "jump over" the line between 1 Hz GPS fixes.
class TimingGate {
    var latRad;     // Double, radians
    var lonRad;     // Double, radians
    var heading;    // Float radians (0 = north, clockwise) or null if unknown
    var radius;     // Float, metres
    private var _cosLat;

    function initialize(latRad, lonRad, heading, radius) {
        self.latRad = latRad.toDouble();
        self.lonRad = lonRad.toDouble();
        self.heading = heading;
        self.radius = radius.toFloat();
        _cosLat = Math.cos(self.latRad).toDouble();
    }

    static function fromLocation(loc as Position.Location, heading, radius) as TimingGate {
        var r = loc.toRadians();
        return new TimingGate(r[0], r[1], heading, radius);
    }

    // Storage format: [latDeg, lonDeg] or [latDeg, lonDeg, headingRad]
    static function fromStorage(data, radius) {
        if (data == null || !(data instanceof Array) || data.size() < 2) {
            return null;
        }
        var heading = data.size() > 2 ? data[2].toFloat() : null;
        return new TimingGate(Math.toRadians(data[0].toDouble()),
                              Math.toRadians(data[1].toDouble()),
                              heading, radius);
    }

    function toStorage() as Array {
        var lat = Math.toDegrees(latRad).toDouble();
        var lon = Math.toDegrees(lonRad).toDouble();
        if (heading != null) {
            return [lat, lon, heading];
        }
        return [lat, lon];
    }

    function isDirectional() as Boolean {
        return heading != null;
    }

    // Flat-earth projection around the gate (accurate to cm over a few hundred m).
    private function toLocal(lat, lon) as Array {
        return [(lon - lonRad) * _cosLat * EARTH_RADIUS_M,
                (lat - latRad) * EARTH_RADIUS_M];
    }

    // Returns the fraction (0..1) along the segment prev->cur at which the gate
    // was crossed, or -1.0 if it wasn't crossed on this segment.
    function crossingFraction(lat0, lon0, lat1, lon1) as Float {
        var a = toLocal(lat0, lon0);
        var b = toLocal(lat1, lon1);
        var dx = b[0] - a[0];
        var dy = b[1] - a[1];
        var len2 = dx * dx + dy * dy;

        if (len2 < 0.25) {        // moved less than 0.5 m: stationary / jitter
            return -1.0;
        }
        if (len2 > 250000.0) {    // jumped more than 500 m: bad fix or GPS gap
            return -1.0;
        }

        // Point on the segment closest to the gate centre
        var t = -(a[0] * dx + a[1] * dy) / len2;
        if (t < 0 || t >= 1) {
            return -1.0;
        }
        var cx = a[0] + t * dx;
        var cy = a[1] + t * dy;
        if (cx * cx + cy * cy > radius * radius) {
            return -1.0;
        }

        // If we know which way the track runs here, ignore wrong-way passes
        // (e.g. an opposite-direction straight that runs close by).
        if (heading != null) {
            var dot = dx * Math.sin(heading) + dy * Math.cos(heading);
            if (dot <= 0) {
                return -1.0;
            }
        }
        return t.toFloat();
    }
}
