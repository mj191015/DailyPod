//
//  BackgroundTestViewController.swift
//  Test A: does CMHeadphoneMotionManager keep delivering samples in the background / with the screen locked?
//
//  Mode 1: nothing special (the app is suspended by iOS as usual).
//  Mode 2: audio session (.playback) + endless silent audio so UIBackgroundModes=audio keeps the app alive.
//  Mode 3: mode 2, plus log audio interruptions and try to resume.
//  Mode 4: NO audio. Background location updates (UIBackgroundModes=location) keep the app alive instead
//          (coarse accuracy, 3 km).
//  Mode 5: NO audio. Same as mode 4 but with best (GPS) accuracy.
//
//  NOTE: UIBackgroundModes=audio is declared in Info.plist for every mode (a plist cannot change at runtime).
//  Mode 1 simply never starts an audio session or playback, so the declaration is unused.
//

import UIKit
import CoreMotion
import AVFoundation
import CoreLocation

final class BackgroundTestViewController: UIViewController, CMHeadphoneMotionManagerDelegate, CLLocationManagerDelegate {

    private let motion = CMHeadphoneMotionManager()
    private let location = CLLocationManager()
    private var locationFixes = 0
    private let seg = UISegmentedControl(items: ["1: none", "2: audio", "3: audio+resume", "4: loc low", "5: loc best"])
    private var startButton: UIButton!
    private let statusLabel = TTUI.label("Idle", size: 15)
    private let countLabel = TTUI.label("samples: 0", size: 22, mono: true)
    private let gapLabel = TTUI.label("since last sample: -", size: 22, mono: true)
    private let logView = TTUI.logView()

    private var samples: TTLogger?
    private var events: TTLogger?
    private var player: AVAudioPlayer?
    private var running = false
    private var mode = 1
    private var count = 0
    private var lastSampleUptime: Double?
    private var runStartUptime = 0.0
    private var uiTimer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Test A: Background"
        view.backgroundColor = .systemBackground
        seg.selectedSegmentIndex = 0
        startButton = TTUI.button("Start", target: self, action: #selector(toggle))
        let hint = TTUI.label("Start, then go Home / lock the screen, wait, and reopen. Samples keep being written to Documents/bgtest_*.csv.", size: 12)
        TTUI.stack(in: self, [seg, startButton, statusLabel, countLabel, gapLabel, hint, logView])
        motion.delegate = self
        location.delegate = self
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent && running { stop(reason: "screen closed") }
    }

    // MARK: - Control

    @objc private func toggle() {
        running ? stop(reason: "button") : start()
    }

    private func start() {
        guard motion.isDeviceMotionAvailable else {
            statusLabel.text = "Headphone motion not available"
            return
        }
        mode = seg.selectedSegmentIndex + 1
        seg.isEnabled = false
        let stamp = TTFiles.stamp()
        samples = TTLogger(name: "bgtest_mode\(mode)_\(stamp).csv",
                           header: "mode,wall_iso,wall_epoch,uptime_s,motion_timestamp")
        events = TTLogger(name: "bgtest_mode\(mode)_\(stamp)_events.csv",
                          header: "wall_iso,wall_epoch,uptime_s,event")
        count = 0
        lastSampleUptime = nil
        runStartUptime = TTClock.uptimeNow()

        let dev = UIDevice.current
        event("start mode=\(mode) device=\(dev.model) iOS=\(dev.systemVersion) motionAuth=\(CMHeadphoneMotionManager.authorizationStatus().rawValue) locationAuth=\(location.authorizationStatus.rawValue)")

        if mode == 2 || mode == 3 { startAudio() }
        if mode >= 4 { startLocation() }
        observe()

        motion.startDeviceMotionUpdates(to: .main) { [weak self] m, error in
            guard let self = self else { return }
            if let error = error {
                self.event("motion error: \(error.localizedDescription)")
                return
            }
            guard let m = m else { return }
            let up = TTClock.uptimeNow()
            self.count += 1
            self.lastSampleUptime = up
            self.samples?.write("\(self.mode),\(TTClock.isoNow()),\(TTClock.epochNow()),\(up),\(m.timestamp)")
        }

        running = true
        startButton.setTitle("Stop", for: .normal)
        startButton.backgroundColor = .systemRed
        statusLabel.text = "Running mode \(mode) -> \(samples?.url.lastPathComponent ?? "")"
        uiTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.refresh() }
    }

    private func stop(reason: String) {
        motion.stopDeviceMotionUpdates()
        player?.stop()
        player = nil
        if mode == 2 || mode == 3 { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
        if mode >= 4 { stopLocation() }
        NotificationCenter.default.removeObserver(self)
        uiTimer?.invalidate()
        uiTimer = nil
        event("stop (\(reason)) samples=\(count)")
        samples?.close()
        events?.close()
        running = false
        seg.isEnabled = true
        startButton.setTitle("Start", for: .normal)
        startButton.backgroundColor = .systemBlue
        statusLabel.text = "Stopped. samples=\(count)"
    }

    private func refresh() {
        countLabel.text = "samples: \(count)"
        if let last = lastSampleUptime {
            gapLabel.text = String(format: "since last sample: %.1f s", TTClock.uptimeNow() - last)
        } else {
            gapLabel.text = String(format: "since last sample: none yet (%.0f s)", TTClock.uptimeNow() - runStartUptime)
        }
    }

    // MARK: - Audio (modes 2, 3)

    private func startAudio() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
            let p = try AVAudioPlayer(contentsOf: TTAudio.silenceURL())
            p.numberOfLoops = -1
            p.prepareToPlay()
            p.play()
            player = p
            event("audio started route=\(TTAudio.routeDescription())")
        } catch {
            event("audio start failed: \(error.localizedDescription)")
        }
    }

    private func resumeAudio() {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            let ok = player?.play() ?? false
            event("resume attempt: play() returned \(ok)")
        } catch {
            event("resume failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Location keep-alive (mode 4)

    private func startLocation() {
        locationFixes = 0
        location.desiredAccuracy = (mode == 5) ? kCLLocationAccuracyBest : kCLLocationAccuracyThreeKilometers
        location.distanceFilter = kCLDistanceFilterNone
        location.pausesLocationUpdatesAutomatically = false
        location.allowsBackgroundLocationUpdates = true
        location.showsBackgroundLocationIndicator = true
        event("location start accuracy=\(mode == 5 ? "best" : "3km") auth=\(location.authorizationStatus.rawValue)")
        location.requestWhenInUseAuthorization()
        location.startUpdatingLocation()
    }

    private func stopLocation() {
        location.stopUpdatingLocation()
        location.allowsBackgroundLocationUpdates = false
        event("location stop fixes=\(locationFixes)")
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        event("location authorization=\(manager.authorizationStatus.rawValue) (3=whenInUse 4=always 2=denied 0=notDetermined)")
        if running && mode >= 4 && (manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways) {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        locationFixes += 1
        if locationFixes == 1 || locationFixes % 20 == 0 { event("location fix #\(locationFixes)") }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        event("location error: \(error.localizedDescription)")
    }

    // MARK: - Notifications / events

    private func observe() {
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(didEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        nc.addObserver(self, selector: #selector(willEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        if mode == 2 || mode == 3 {
            nc.addObserver(self, selector: #selector(routeChanged(_:)), name: AVAudioSession.routeChangeNotification, object: nil)
            nc.addObserver(self, selector: #selector(interrupted(_:)), name: AVAudioSession.interruptionNotification, object: nil)
        }
    }

    @objc private func didEnterBackground() { event("app did enter background") }
    @objc private func willEnterForeground() { event("app will enter foreground") }

    @objc private func routeChanged(_ n: Notification) {
        let reason = (n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) ?? 0
        event("route change reason=\(reason) route=\(TTAudio.routeDescription())")
    }

    @objc private func interrupted(_ n: Notification) {
        let typeRaw = (n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) ?? 0
        let type = AVAudioSession.InterruptionType(rawValue: typeRaw)
        let optRaw = (n.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt) ?? 0
        let shouldResume = AVAudioSession.InterruptionOptions(rawValue: optRaw).contains(.shouldResume)
        event("audio interruption type=\(type == .began ? "began" : "ended") shouldResume=\(shouldResume)")
        if mode == 3 && type == .ended { resumeAudio() }
    }

    func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) { event("headphones connected") }
    func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) { event("headphones disconnected") }

    private func event(_ text: String) {
        let clean = text.replacingOccurrences(of: "\"", with: "'")
        events?.write("\(TTClock.isoNow()),\(TTClock.epochNow()),\(TTClock.uptimeNow()),\"\(clean)\"")
        TTUI.appendLog(logView, "\(TTClock.isoNow().suffix(13)) \(clean)")
    }
}
