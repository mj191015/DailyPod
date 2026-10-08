//
//  AlertTestViewController.swift
//  Test C: does the alert sound behave as intended (screen on / Home / locked, silent switch, Focus)?
//
//  Stage 1 alert: sound for 10 s, stops by itself, 3 s of nothing, then stage 2 starts right away.
//  Stage 2 alert: repeats until the Stop button is pressed.
//  Also: a local notification (with sound) can be scheduled for comparison.
//
//  The audio session stays active during the 3 s gap on purpose; whether the app is still alive to start
//  stage 2 afterwards is exactly what this test shows. Every event goes to Documents/alerttest_*.csv.
//

import UIKit
import AVFoundation
import UserNotifications

final class AlertTestViewController: UIViewController, UNUserNotificationCenterDelegate {

    private let firstSeconds = 10.0
    private let gapSeconds = 3.0

    private let routeLabel = TTUI.label("route: -", size: 14)
    private let phaseLabel = TTUI.label("Idle", size: 22, mono: true)
    private let logView = TTUI.logView()
    private var player: AVAudioPlayer?
    private var token = 0                 // invalidates timers scheduled by an earlier run
    private var logger: TTLogger?
    private var routeTimer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Test C: Alert"
        view.backgroundColor = .systemBackground
        logger = TTLogger(name: "alerttest_\(TTFiles.stamp()).csv", header: "wall_iso,wall_epoch,uptime_s,event,route")
        let b1 = TTUI.button("Stage 1 alert (10 s -> 3 s gap -> stage 2)", target: self, action: #selector(tapFirst))
        let b2 = TTUI.button("Stage 2 alert (repeat)", target: self, action: #selector(tapSecond))
        let bs = TTUI.button("Stop", target: self, action: #selector(tapStop))
        bs.backgroundColor = .systemRed
        let bn = TTUI.button("Local notification in 5 s", target: self, action: #selector(tapNotification))
        bn.backgroundColor = .systemGreen
        TTUI.stack(in: self, [b1, b2, bs, bn, phaseLabel, routeLabel, logView])

        UNUserNotificationCenter.current().delegate = self
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(interrupted(_:)), name: AVAudioSession.interruptionNotification, object: nil)
        nc.addObserver(self, selector: #selector(routeChanged(_:)), name: AVAudioSession.routeChangeNotification, object: nil)
        nc.addObserver(self, selector: #selector(didEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        nc.addObserver(self, selector: #selector(willEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        routeTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.routeLabel.text = "route: \(TTAudio.routeDescription())"
        }
        event("screen opened silentSwitchAndFocusAreManual iOS=\(UIDevice.current.systemVersion)")
    }

    deinit {
        routeTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
        logger?.close()
    }

    // MARK: - Alerts

    @objc private func tapFirst() { startFirst() }
    @objc private func tapSecond() { token += 1; startSecond(auto: false) }
    @objc private func tapStop() { stop(reason: "manual stop") }

    private func startFirst() {
        token += 1
        let mine = token
        guard play() else { return }
        phaseLabel.text = "STAGE 1 (10 s)"
        event("stage1 start")
        DispatchQueue.main.asyncAfter(deadline: .now() + firstSeconds) { [weak self] in
            guard let self = self, mine == self.token else { return }
            self.player?.stop()
            self.phaseLabel.text = "GAP (3 s)"
            self.event("stage1 end (auto stop)")
            DispatchQueue.main.asyncAfter(deadline: .now() + self.gapSeconds) { [weak self] in
                guard let self = self, mine == self.token else { return }
                self.event("gap over, starting stage2")
                self.startSecond(auto: true)
            }
        }
    }

    private func startSecond(auto: Bool) {
        guard play() else { return }
        phaseLabel.text = "STAGE 2 (repeating)"
        event(auto ? "stage2 start (after stage1)" : "stage2 start (manual)")
    }

    private func stop(reason: String) {
        token += 1
        player?.stop()
        phaseLabel.text = "Stopped"
        event(reason)
    }

    @discardableResult
    private func play() -> Bool {
        do {
            let s = AVAudioSession.sharedInstance()
            try s.setCategory(.playback, mode: .default, options: [])
            try s.setActive(true)
            let p = try AVAudioPlayer(contentsOf: TTAudio.alertURL())
            p.numberOfLoops = -1
            p.volume = 1.0
            p.prepareToPlay()
            let ok = p.play()
            player = p
            if !ok { event("play() returned false") }
            return ok
        } catch {
            event("audio error: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Local notification

    @objc private func tapNotification() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard granted else { self.event("notification permission denied"); return }
                let c = UNMutableNotificationContent()
                c.title = "Alert test"
                c.body = "Local notification with sound"
                c.sound = .default
                let req = UNNotificationRequest(identifier: UUID().uuidString, content: c,
                                                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false))
                center.add(req) { err in
                    DispatchQueue.main.async {
                        self.event(err == nil ? "local notification scheduled (+5 s)" : "notification error: \(err!.localizedDescription)")
                    }
                }
            }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        event("local notification delivered while app in foreground")
        completionHandler([.banner, .sound])
    }

    // MARK: - Observers

    @objc private func interrupted(_ n: Notification) {
        let raw = (n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) ?? 0
        event("audio interruption \(AVAudioSession.InterruptionType(rawValue: raw) == .began ? "began" : "ended")")
    }

    @objc private func routeChanged(_ n: Notification) {
        let reason = (n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) ?? 0
        event("route change reason=\(reason)")
    }

    @objc private func didEnterBackground() { event("app did enter background") }
    @objc private func willEnterForeground() { event("app will enter foreground") }

    private func event(_ text: String) {
        let clean = text.replacingOccurrences(of: "\"", with: "'")
        let route = TTAudio.routeDescription().replacingOccurrences(of: "\"", with: "'")
        logger?.write("\(TTClock.isoNow()),\(TTClock.epochNow()),\(TTClock.uptimeNow()),\"\(clean)\",\"\(route)\"")
        TTUI.appendLog(logView, "\(TTClock.isoNow().suffix(13)) \(clean)")
    }
}
