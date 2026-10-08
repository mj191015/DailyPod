//
//  AlarmKitAlertViewController.swift
//  First alert through AlarmKit (iOS 26+): the system shows the alarm screen over the Home screen and the
//  Lock Screen (the screen turns on), like the Clock app. The stop control is provided by the system; its look
//  cannot be customised.
//
//  Flow: button -> alarm scheduled 10 s ahead -> (you go Home / lock) -> alarm fires.
//        Stop pressed in the system UI -> alarm ends.
//        Not pressed -> this app asks AlarmManager to stop the alarm 10 s after it started alerting.
//  A silent audio loop keeps this process alive while waiting so that the 10 s stop can run.
//

import UIKit
import SwiftUI
import AVFoundation
import AlarmKit
import AppIntents

@available(iOS 26.1, *)
struct FirstAlertMetadata: AlarmMetadata {}

/// Runs when the "X" button on the alarm screen is tapped: stops that alarm.
/// It appends to Documents/xalarmkit_intent.csv so we can see whether (and where) it ran.
@available(iOS 26.1, *)
struct XStopIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "X"
    static var description = IntentDescription("Stop the first alert")

    @Parameter(title: "alarmID") var alarmID: String

    init(alarmID: String) { self.alarmID = alarmID }
    init() { self.alarmID = "" }

    func perform() async throws -> some IntentResult {
        let log = TTLogger(name: "xalarmkit_intent.csv", header: "wall_iso,wall_epoch,uptime_s,event", append: true)
        log.write("\(TTClock.isoNow()),\(TTClock.epochNow()),\(TTClock.uptimeNow()),\"X intent started id=\(alarmID)\"")
        if let id = UUID(uuidString: alarmID) {
            do {
                try AlarmManager.shared.stop(id: id)
                log.write("\(TTClock.isoNow()),\(TTClock.epochNow()),\(TTClock.uptimeNow()),\"alarm stopped by X\"")
            } catch {
                log.write("\(TTClock.isoNow()),\(TTClock.epochNow()),\(TTClock.uptimeNow()),\"stop failed: \(error)\"")
            }
        }
        log.close()
        return .result()
    }
}

@available(iOS 26.1, *)
final class AlarmKitAlertViewController: UIViewController {

    private let manager = AlarmManager.shared
    private let statusLabel = TTUI.label("Ready", size: 20, mono: true)
    private let logView = TTUI.logView()

    private var logger: TTLogger?
    private var alarmID: UUID?
    private var scheduled = false
    private var autoStopArmed = false
    private var keepAlive: AVAudioPlayer?
    private var updatesTask: Task<Void, Never>?
    private var alerting = false
    private var overlay: UIView?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "1차 알람 (AlarmKit)"
        view.backgroundColor = .systemBackground
        logger = TTLogger(name: "xalarmkit_\(TTFiles.stamp()).csv", header: "wall_iso,wall_epoch,uptime_s,app,event")
        let start = TTUI.button("10초 뒤 알람 (누르고 홈/잠금)", target: self, action: #selector(schedule))
        let cancel = TTUI.button("알람 취소", target: self, action: #selector(cancelAlarm))
        cancel.backgroundColor = .systemGray
        let hint = TTUI.label("알람 화면에 X 버튼이 보이고, 누르면 알람이 꺼져야 합니다. (시스템 기본 끄기 버튼은 없앨 수 없음)", size: 12)
        TTUI.stack(in: self, [statusLabel, start, cancel, hint, logView])
        observeUpdates()
        NotificationCenter.default.addObserver(self, selector: #selector(appBecameActive),
                                               name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    deinit {
        updatesTask?.cancel()
        NotificationCenter.default.removeObserver(self)
        overlay?.removeFromSuperview()
    }

    // MARK: - Actions

    @objc private func schedule() {
        guard !scheduled else { return }
        Task { @MainActor in
            do {
                let auth = try await manager.requestAuthorization()
                log("authorization: \(auth)")
                guard auth == .authorized else {
                    statusLabel.text = "알람 권한 필요"
                    return
                }

                let id = UUID()
                // The system stop control (slide to stop on the Lock Screen) is always there and cannot be removed.
                // This adds our own "X" button next to it.
                let xButton = AlarmButton(text: "X", textColor: .white, systemImageName: "xmark")
                let alert = AlarmPresentation.Alert(title: "1차 알림",
                                                    secondaryButton: xButton,
                                                    secondaryButtonBehavior: .custom)
                let attributes = AlarmAttributes<FirstAlertMetadata>(
                    presentation: AlarmPresentation(alert: alert),
                    metadata: FirstAlertMetadata(),
                    tintColor: Color.red)
                let fireAt = Date().addingTimeInterval(10)
                let config = AlarmManager.AlarmConfiguration<FirstAlertMetadata>.alarm(
                    schedule: .fixed(fireAt),
                    attributes: attributes,
                    stopIntent: nil,
                    secondaryIntent: XStopIntent(alarmID: id.uuidString),
                    sound: .default)

                startKeepAlive()
                _ = try await manager.schedule(id: id, configuration: config)
                alarmID = id
                scheduled = true
                autoStopArmed = false
                statusLabel.text = "10초 뒤 알람 예약됨"
                log("alarm scheduled for \(TTClock.isoNow()) +10 s")
            } catch {
                stopKeepAlive()
                statusLabel.text = "예약 실패"
                log("schedule failed: \(error)")
            }
        }
    }

    @objc private func cancelAlarm() {
        guard let id = alarmID else { return }
        try? manager.cancel(id: id)
        finish(reason: "cancelled by button")
    }

    // MARK: - Observing the alarm

    private func observeUpdates() {
        updatesTask = Task { [weak self] in
            for await alarms in AlarmManager.shared.alarmUpdates {
                await MainActor.run { self?.handle(alarms) }
            }
        }
    }

    private func handle(_ alarms: [Alarm]) {
        guard scheduled, let id = alarmID else { return }
        guard let alarm = alarms.first(where: { $0.id == id }) else {
            finish(reason: "alarm gone (stopped or finished)")
            return
        }
        log("alarm state: \(alarm.state)")
        alerting = (alarm.state == .alerting)
        if alerting { showOverlay() }
        if alarm.state == .alerting && !autoStopArmed {
            autoStopArmed = true
            statusLabel.text = "울리는 중"
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                guard let self = self, self.scheduled, self.alarmID == id else { return }
                do {
                    try self.manager.stop(id: id)
                    self.log("auto stop after 10 s requested")
                } catch {
                    self.log("auto stop failed: \(error)")
                }
            }
        }
    }

    private func finish(reason: String) {
        guard scheduled else { return }
        scheduled = false
        autoStopArmed = false
        alerting = false
        hideOverlay()
        stopKeepAlive()
        statusLabel.text = "끝 (\(reason))"
        log("finished: \(reason)")
    }

    // MARK: - Full-screen X while the app is open

    /// The system only shows a small banner when the phone is unlocked. While this app is in the foreground we
    /// can draw our own full-screen alert instead. (From the Home screen the app cannot bring itself forward.)
    private func showOverlay() {
        guard overlay == nil, UIApplication.shared.applicationState == .active,
              let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).flatMap({ $0.windows }).first(where: { $0.isKeyWindow })
        else { return }
        let v = UIView(frame: window.bounds)
        v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        v.backgroundColor = .systemRed

        let x = UIButton(type: .system)          // small round button: only this circle dismisses the alert
        x.setTitle("X", for: .normal)
        x.titleLabel?.font = .systemFont(ofSize: 40, weight: .bold)
        x.setTitleColor(.systemRed, for: .normal)
        x.backgroundColor = .white
        x.layer.cornerRadius = 44
        x.frame = CGRect(x: 0, y: 0, width: 88, height: 88)
        x.center = CGPoint(x: v.bounds.midX, y: v.bounds.midY)
        x.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin, .flexibleTopMargin, .flexibleBottomMargin]
        x.addTarget(self, action: #selector(tapOverlayX), for: .touchUpInside)

        let title = UILabel(frame: CGRect(x: 0, y: v.bounds.midY - 130, width: v.bounds.width, height: 40))
        title.text = "1차 알림"
        title.textColor = .white
        title.font = .systemFont(ofSize: 28, weight: .bold)
        title.textAlignment = .center
        title.autoresizingMask = [.flexibleWidth, .flexibleBottomMargin]

        v.addSubview(title)
        v.addSubview(x)
        window.addSubview(v)
        overlay = v
        log("full-screen X shown (app in foreground)")
    }

    private func hideOverlay() {
        overlay?.removeFromSuperview()
        overlay = nil
    }

    @objc private func appBecameActive() {
        if alerting { showOverlay() }
    }

    @objc private func tapOverlayX() {
        guard let id = alarmID else { return }
        do {
            try manager.stop(id: id)
            log("X pressed in full-screen overlay: stop requested")
        } catch {
            log("stop failed: \(error)")
        }
        hideOverlay()
    }

    // MARK: - Keep this process alive while waiting

    private func startKeepAlive() {
        do {
            let s = AVAudioSession.sharedInstance()
            try s.setCategory(.playback, mode: .default, options: [])
            try s.setActive(true)
            let p = try AVAudioPlayer(contentsOf: TTAudio.silenceURL())
            p.numberOfLoops = -1
            p.play()
            keepAlive = p
            log("keep-alive silent audio started")
        } catch {
            log("keep-alive failed: \(error.localizedDescription)")
        }
    }

    private func stopKeepAlive() {
        keepAlive?.stop()
        keepAlive = nil
    }

    // MARK: - Log

    private func log(_ event: String) {
        let s = UIApplication.shared.applicationState
        let app = s == .active ? "active" : (s == .background ? "background" : "inactive")
        let clean = event.replacingOccurrences(of: "\"", with: "'")
        logger?.write("\(TTClock.isoNow()),\(TTClock.epochNow()),\(TTClock.uptimeNow()),\(app),\"\(clean)\"")
        TTUI.appendLog(logView, "\(TTClock.isoNow().suffix(13)) \(clean)")
    }
}
