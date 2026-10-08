//
//  StretchMath.swift
//  Distance measures between two attitude recordings. Each recording is [[pitch, roll, yaw]] in radians.
//  Written from the textbook definitions only; no external library or third-party code is used.
//

import Foundation

enum StretchMath {

    /// Removes 2*pi jumps from one angle series so it is continuous.
    static func unwrap(_ a: [Double]) -> [Double] {
        guard var prev = a.first else { return a }
        var offset = 0.0
        var out = [prev]
        for v in a.dropFirst() {
            let d = v - prev
            if d > Double.pi { offset -= 2 * Double.pi }
            else if d < -Double.pi { offset += 2 * Double.pi }
            out.append(v + offset)
            prev = v
        }
        return out
    }

    /// Unwraps each of the three axes independently.
    static func unwrapAxes(_ s: [[Double]]) -> [[Double]] {
        guard !s.isEmpty else { return s }
        let cols = (0..<3).map { k in unwrap(s.map { $0[k] }) }
        return (0..<s.count).map { i in [cols[0][i], cols[1][i], cols[2][i]] }
    }

    private static func sq(_ a: [Double], _ b: [Double]) -> Double {
        var s = 0.0
        for k in 0..<3 { let d = a[k] - b[k]; s += d * d }
        return s
    }

    /// Linear resampling by index so that the series has exactly n points.
    static func resample(_ s: [[Double]], to n: Int) -> [[Double]] {
        guard s.count > 1, n > 1 else { return s.isEmpty ? [] : Array(repeating: s[0], count: max(n, 1)) }
        var out: [[Double]] = []
        out.reserveCapacity(n)
        for i in 0..<n {
            let pos = Double(i) * Double(s.count - 1) / Double(n - 1)
            let lo = Int(pos.rounded(.down))
            let hi = min(lo + 1, s.count - 1)
            let f = pos - Double(lo)
            out.append((0..<3).map { s[lo][$0] * (1 - f) + s[hi][$0] * f })
        }
        return out
    }

    /// (a) Simple comparison: stretch the attempt to the reference length, then take the mean over
    /// time of the three-axis squared difference at the same time index.
    static func simpleDistance(reference: [[Double]], attempt: [[Double]]) -> Double {
        guard !reference.isEmpty, !attempt.isEmpty else { return .nan }
        let r = resample(attempt, to: reference.count)
        var total = 0.0
        for i in 0..<reference.count { total += sq(reference[i], r[i]) }
        return total / Double(reference.count)
    }

    /// (b) Dynamic time warping with a Sakoe-Chiba band.
    /// - local cost: three-axis squared distance
    /// - band half-width: `windowFraction` x reference length (widened to |n - m| when the lengths differ more,
    ///   otherwise no warping path would exist)
    /// - result: total path cost divided by the longer of the two lengths
    static func dtwDistance(reference: [[Double]], attempt: [[Double]], windowFraction: Double = 0.4) -> Double {
        let n = reference.count, m = attempt.count
        guard n > 0, m > 0 else { return .nan }
        let w = max(Int((Double(n) * windowFraction).rounded()), abs(n - m))
        var prev = [Double](repeating: .infinity, count: m + 1)
        prev[0] = 0
        for i in 1...n {
            var cur = [Double](repeating: .infinity, count: m + 1)
            let lo = max(1, i - w), hi = min(m, i + w)
            if lo <= hi {
                for j in lo...hi {
                    let cost = sq(reference[i - 1], attempt[j - 1])
                    cur[j] = cost + min(prev[j], prev[j - 1], cur[j - 1])
                }
            }
            prev = cur
        }
        return prev[m] / Double(max(n, m))
    }
}
