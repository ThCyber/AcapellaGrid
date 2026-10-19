import Foundation
import CoreMedia

/// All timing in the app is expressed in mach host time — the one clock that
/// AVAudioEngine (metronome), AVPlayer (backing tracks) and AVCaptureSession
/// (camera + mic) can all be related to. Scheduling everything against this
/// clock, instead of "start now", is what keeps the four tracks locked together.
enum HostTime {
    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    static var now: UInt64 { mach_absolute_time() }

    static func seconds(_ ticks: UInt64) -> Double {
        Double(ticks) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
    }

    static func ticks(_ seconds: Double) -> UInt64 {
        UInt64((max(0, seconds) * 1_000_000_000 * Double(timebase.denom) / Double(timebase.numer)).rounded())
    }

    /// Signed difference `a - b` in seconds.
    static func delta(_ a: UInt64, _ b: UInt64) -> Double {
        a >= b ? seconds(a - b) : -seconds(b - a)
    }

    static func offset(_ base: UInt64, by seconds: Double) -> UInt64 {
        seconds >= 0 ? base + ticks(seconds) : base - ticks(-seconds)
    }

    static func cmTime(_ ticks: UInt64) -> CMTime {
        CMClockMakeHostTimeFromSystemUnits(ticks)
    }
}
