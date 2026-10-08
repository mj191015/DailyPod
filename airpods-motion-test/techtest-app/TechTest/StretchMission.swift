//
//  StretchMission.swift
//  The target posture sequence for the stretch mission, as plain data (Foundation only).
//
//  To change the mission, edit `keyframes`. The same array can be turned into a DTW reference template with
//  `StretchMission.samples(hz:)`, which returns [[pitch, roll, yaw]] in radians, the shape StretchMath expects.
//

import Foundation

struct StretchKeyframe {
    let t: Double          // seconds from mission start at which this pose is reached
    let pitch: Double      // radians
    let roll: Double       // radians
    let yaw: Double        // radians (relative to the straight-ahead calibration)
    let hold: Double       // seconds to stay in this pose after reaching it
    let label: String      // shown to the user while moving to / holding this pose
    var recenter: Bool = false   // neutral hold: the screen re-zeroes to the user's posture while they stay still
}

enum StretchMission {

    static let name = "목 옆으로 기울이기"

    /// roll 0 -> +0.5 rad (hold 3 s) -> 0 (hold 1.5 s, re-zero) -> -0.5 rad (hold 3 s) -> 0 (hold 1.5 s, re-zero)
    static let keyframes: [StretchKeyframe] = [
        StretchKeyframe(t: 0,    pitch: 0, roll: 0,    yaw: 0, hold: 0,   label: "정면"),
        StretchKeyframe(t: 2,    pitch: 0, roll: 0.5,  yaw: 0, hold: 3,   label: "오른쪽으로 기울이기"),
        StretchKeyframe(t: 7,    pitch: 0, roll: 0,    yaw: 0, hold: 1.5, label: "정면으로 돌아와 가만히", recenter: true),
        StretchKeyframe(t: 10.5, pitch: 0, roll: -0.5, yaw: 0, hold: 3,   label: "왼쪽으로 기울이기"),
        StretchKeyframe(t: 15.5, pitch: 0, roll: 0,    yaw: 0, hold: 1.5, label: "정면으로 돌아와 가만히", recenter: true)
    ]

    static var duration: Double {
        guard let last = keyframes.last else { return 0 }
        return last.t + last.hold
    }

    /// Target pose at time `t` (linear movement between keyframes, constant during a hold).
    static func pose(at t: Double) -> (pitch: Double, roll: Double, yaw: Double) {
        guard let first = keyframes.first else { return (0, 0, 0) }
        if t <= first.t { return (first.pitch, first.roll, first.yaw) }
        for i in 0..<keyframes.count {
            let k = keyframes[i]
            let holdEnd = k.t + k.hold
            if t <= holdEnd { return (k.pitch, k.roll, k.yaw) }
            if i + 1 < keyframes.count {
                let next = keyframes[i + 1]
                if t < next.t {
                    let f = (t - holdEnd) / (next.t - holdEnd)
                    return (k.pitch + (next.pitch - k.pitch) * f,
                            k.roll + (next.roll - k.roll) * f,
                            k.yaw + (next.yaw - k.yaw) * f)
                }
            }
        }
        let last = keyframes[keyframes.count - 1]
        return (last.pitch, last.roll, last.yaw)
    }

    /// Text for the current step, e.g. "오른쪽으로 기울이기 3초" while holding, or just the label while moving.
    static func stepText(at t: Double) -> String {
        for k in keyframes {
            if t < k.t { return k.label }
            if k.hold > 0 && t <= k.t + k.hold {
                return "\(k.label) \(Int((k.t + k.hold - t).rounded(.up)))초"
            }
        }
        return "완료"
    }

    /// True while the target is in a neutral hold (after a short settling time): the screen may re-zero to the user's posture.
    static func isRecenterWindow(at t: Double) -> Bool {
        keyframes.contains { $0.recenter && t >= $0.t + 0.4 && t <= $0.t + $0.hold }
    }

    /// The whole mission as evenly spaced samples, for use as a DTW reference.
    static func samples(hz: Double) -> [[Double]] {
        let n = Int(duration * hz) + 1
        return (0..<n).map { i in
            let p = pose(at: Double(i) / hz)
            return [p.pitch, p.roll, p.yaw]
        }
    }
}
