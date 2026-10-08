//
//  TechTestCommon.swift
//  Shared helpers for the three technology feasibility tests (A: background, B: stretch, C: alert).
//

import UIKit
import AVFoundation

enum TTFiles {
    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f.string(from: Date())
    }
}

enum TTClock {
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Wall clock as ISO-8601 with milliseconds.
    static func isoNow() -> String { iso.string(from: Date()) }
    /// Wall clock as epoch seconds.
    static func epochNow() -> Double { Date().timeIntervalSince1970 }
    /// Monotonic seconds since boot (does not advance while the device sleeps).
    static func uptimeNow() -> Double { ProcessInfo.processInfo.systemUptime }
}

/// Append-only text/CSV writer. Every write goes straight to the file (no in-memory buffering),
/// so data survives if the app is killed.
final class TTLogger {
    let url: URL
    private var handle: FileHandle?
    private let queue = DispatchQueue(label: "TTLogger")

    /// - Parameter append: keep an existing file and add to it (header is written only for a new file).
    init(name: String, header: String, append: Bool = false) {
        url = TTFiles.documents.appendingPathComponent(name)
        let exists = FileManager.default.fileExists(atPath: url.path)
        if !(append && exists) {
            FileManager.default.createFile(atPath: url.path, contents: (header + "\n").data(using: .utf8))
        }
        handle = try? FileHandle(forWritingTo: url)
        _ = try? handle?.seekToEnd()
    }

    func write(_ line: String) {
        guard let data = (line + "\n").data(using: .utf8) else { return }
        queue.async { [weak self] in
            self?.handle?.write(data)
        }
    }

    func close() {
        queue.sync {
            try? handle?.close()
            handle = nil
        }
    }

    deinit { try? handle?.close() }
}

/// Generates short WAV files at runtime so the app needs no bundled audio.
enum TTAudio {
    private static let rate = 44100

    private static func wav(_ samples: [Int16]) -> Data {
        var d = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        let dataSize = UInt32(samples.count * 2)
        d.append("RIFF".data(using: .ascii)!); u32(36 + dataSize)
        d.append("WAVE".data(using: .ascii)!)
        d.append("fmt ".data(using: .ascii)!)
        u32(16); u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate * 2)); u16(2); u16(16)
        d.append("data".data(using: .ascii)!); u32(dataSize)
        for s in samples { u16(UInt16(bitPattern: s)) }
        return d
    }

    private static func write(_ samples: [Int16], name: String) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? wav(samples).write(to: url)
        return url
    }

    /// One second of digital silence (for looping in the background-audio modes).
    static func silenceURL() -> URL {
        write([Int16](repeating: 0, count: rate), name: "tt_silence.wav")
    }

    /// 0.6 s beep (880 Hz) followed by 0.4 s of silence; meant to be looped.
    static func alertURL() -> URL {
        var s = [Int16](repeating: 0, count: rate)
        let beep = Int(Double(rate) * 0.6)
        for i in 0..<beep {
            let t = Double(i) / Double(rate)
            let fade = min(1.0, min(Double(i) / 800.0, Double(beep - i) / 800.0))
            s[i] = Int16(sin(2 * Double.pi * 880 * t) * fade * 28000)
        }
        return write(s, name: "tt_alert.wav")
    }

    static func routeDescription() -> String {
        let outs = AVAudioSession.sharedInstance().currentRoute.outputs
        if outs.isEmpty { return "(no output)" }
        return outs.map { "\($0.portName) [\($0.portType.rawValue)]" }.joined(separator: ", ")
    }
}

enum TTUI {
    static func button(_ title: String, target: Any?, action: Selector) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        b.backgroundColor = .systemBlue
        b.setTitleColor(.white, for: .normal)
        b.layer.cornerRadius = 8
        b.heightAnchor.constraint(equalToConstant: 44).isActive = true
        b.addTarget(target, action: action, for: .touchUpInside)
        return b
    }

    static func label(_ text: String = "", size: CGFloat = 15, mono: Bool = false) -> UILabel {
        let l = UILabel()
        l.text = text
        l.numberOfLines = 0
        l.font = mono ? .monospacedDigitSystemFont(ofSize: size, weight: .regular) : .systemFont(ofSize: size)
        return l
    }

    static func logView() -> UITextView {
        let v = UITextView()
        v.isEditable = false
        v.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        v.backgroundColor = .secondarySystemBackground
        v.layer.cornerRadius = 6
        v.heightAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
        return v
    }

    /// Stack that fills the safe area; the last arranged view (the log) is allowed to stretch.
    static func stack(in vc: UIViewController, _ views: [UIView]) {
        let s = UIStackView(arrangedSubviews: views)
        s.axis = .vertical
        s.spacing = 10
        s.translatesAutoresizingMaskIntoConstraints = false
        vc.view.addSubview(s)
        let g = vc.view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            s.topAnchor.constraint(equalTo: g.topAnchor, constant: 12),
            s.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 16),
            s.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -16),
            s.bottomAnchor.constraint(equalTo: g.bottomAnchor, constant: -12)
        ])
    }

    static func appendLog(_ view: UITextView, _ line: String) {
        view.text = (view.text ?? "") + line + "\n"
        let end = NSRange(location: max(0, view.text.count - 1), length: 1)
        view.scrollRangeToVisible(end)
    }
}
