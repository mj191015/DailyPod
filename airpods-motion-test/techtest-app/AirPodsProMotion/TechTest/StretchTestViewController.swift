//
//  StretchTestViewController.swift
//  Test B: can a stretching motion be told apart from other motions by comparing it to a recorded template?
//
//  Flow: "Record reference" -> 3 s countdown -> 10 s recording -> saved as the template.
//        "Record attempt"   -> same recording, then distance to the template is computed two ways
//                              (a) simple, (b) DTW) and appended to Documents/stretch_attempts.csv.
//

import UIKit
import CoreMotion

final class StretchTestViewController: UIViewController, CMHeadphoneMotionManagerDelegate {

    private enum Kind { case reference, attempt }
    private let recordSeconds = 10.0
    private let countdownSeconds = 3

    private let motion = CMHeadphoneMotionManager()
    private let labelSeg = UISegmentedControl(items: ["Normal (correct)", "Other motion"])
    private var refButton: UIButton!
    private var tryButton: UIButton!
    private let liveLabel = TTUI.label("pitch/roll/yaw: -", size: 14, mono: true)
    private let stateLabel = TTUI.label("Idle", size: 22, mono: true)
    private let resultLabel = TTUI.label("", size: 15, mono: true)
    private let logView = TTUI.logView()

    private var template: [[Double]] = []
    private var recording: [[Double]] = []
    private var recordTimes: [Double] = []
    private var isRecording = false
    private var busy = false
    private var currentKind: Kind = .reference
    private var currentLabel = "normal"
    private var attempts: TTLogger?

    private var templateURL: URL { TTFiles.documents.appendingPathComponent("stretch_template.json") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Test B: Stretch"
        view.backgroundColor = .systemBackground
        labelSeg.selectedSegmentIndex = 0
        refButton = TTUI.button("Record reference", target: self, action: #selector(tapReference))
        tryButton = TTUI.button("Record attempt", target: self, action: #selector(tapAttempt))
        let caption = TTUI.label("Choose the label BEFORE recording an attempt.", size: 12)
        TTUI.stack(in: self, [refButton, caption, labelSeg, tryButton, liveLabel, stateLabel, resultLabel, logView])
        motion.delegate = self
        loadTemplate()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard motion.isDeviceMotionAvailable else {
            log("Headphone motion not available")
            return
        }
        motion.startDeviceMotionUpdates(to: .main) { [weak self] m, error in
            guard let self = self else { return }
            if let error = error { self.log("motion error: \(error.localizedDescription)"); return }
            guard let m = m else { return }
            let a = m.attitude
            self.liveLabel.text = String(format: "pitch %.2f roll %.2f yaw %.2f", a.pitch, a.roll, a.yaw)
            if self.isRecording {
                self.recording.append([a.pitch, a.roll, a.yaw])
                self.recordTimes.append(m.timestamp)
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        motion.stopDeviceMotionUpdates()
    }

    // MARK: - Actions

    @objc private func tapReference() { begin(.reference) }
    @objc private func tapAttempt() {
        if template.isEmpty {
            log("Record a reference first.")
            return
        }
        begin(.attempt)
    }

    private func begin(_ kind: Kind) {
        guard !busy else { return }
        busy = true
        refButton.isEnabled = false
        tryButton.isEnabled = false
        currentKind = kind
        currentLabel = labelSeg.selectedSegmentIndex == 0 ? "normal" : "other"
        recording = []
        recordTimes = []
        countdown(from: countdownSeconds)
    }

    private func countdown(from n: Int) {
        if n == 0 {
            startRecording()
            return
        }
        stateLabel.text = "Get ready... \(n)"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.countdown(from: n - 1) }
    }

    private func startRecording() {
        isRecording = true
        let start = Date()
        func tick() {
            let left = recordSeconds - Date().timeIntervalSince(start)
            if left <= 0 {
                finishRecording()
            } else {
                stateLabel.text = String(format: "REC %.1f s  (%d samples)", left, recording.count)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { tick() }
            }
        }
        tick()
    }

    private func finishRecording() {
        isRecording = false
        let data = StretchMath.unwrapAxes(recording)
        stateLabel.text = "Done (\(data.count) samples)"
        busy = false
        refButton.isEnabled = true
        tryButton.isEnabled = true
        guard data.count > 10 else {
            log("Too few samples (\(data.count)). Are the AirPods connected and worn?")
            return
        }
        switch currentKind {
        case .reference: saveReference(data)
        case .attempt: scoreAttempt(data)
        }
    }

    // MARK: - Reference

    private func saveReference(_ data: [[Double]]) {
        template = data
        if let json = try? JSONSerialization.data(withJSONObject: data) { try? json.write(to: templateURL) }
        writeRaw(data, prefix: "stretch_ref")
        resultLabel.text = "Reference saved (\(data.count) samples)"
        log("reference saved: \(data.count) samples")
    }

    private func loadTemplate() {
        guard let d = try? Data(contentsOf: templateURL),
              let arr = (try? JSONSerialization.jsonObject(with: d)) as? [[Double]], !arr.isEmpty else { return }
        template = arr
        resultLabel.text = "Loaded saved reference (\(arr.count) samples)"
    }

    // MARK: - Attempt

    private func scoreAttempt(_ data: [[Double]]) {
        let simple = StretchMath.simpleDistance(reference: template, attempt: data)
        let t0 = Date()
        let dtw = StretchMath.dtwDistance(reference: template, attempt: data, windowFraction: 0.4)
        let ms = Date().timeIntervalSince(t0) * 1000
        let file = writeRaw(data, prefix: "stretch_try")
        if attempts == nil {
            attempts = TTLogger(name: "stretch_attempts.csv",
                                header: "wall_iso,label,dist_simple,dist_dtw,len_ref,len_try,file",
                                append: true)
        }
        attempts?.write("\(TTClock.isoNow()),\(currentLabel),\(simple),\(dtw),\(template.count),\(data.count),\(file)")
        resultLabel.text = String(format: "label=%@\nsimple=%.5f\ndtw=%.5f", currentLabel, simple, dtw)
        log(String(format: "attempt [%@] simple=%.5f dtw=%.5f (dtw %.0f ms)", currentLabel, simple, dtw, ms))
    }

    @discardableResult
    private func writeRaw(_ data: [[Double]], prefix: String) -> String {
        let name = "\(prefix)_\(TTFiles.stamp()).csv"
        let w = TTLogger(name: name, header: "pitch,roll,yaw")
        for r in data { w.write("\(r[0]),\(r[1]),\(r[2])") }
        w.close()
        return name
    }

    func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) { log("headphones connected") }
    func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) { log("headphones disconnected") }

    private func log(_ s: String) { TTUI.appendLog(logView, "\(TTClock.isoNow().suffix(13)) \(s)") }
}
