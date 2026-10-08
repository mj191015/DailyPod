//
//  BGMPlayer.swift
//  Loud BGM that loops without gaps for the second-stage alert (stretch mission).
//
//  The song is the single bundled file Audio/bgm.<caf|m4a|mp3|wav|aac>; replace that one file to change the song.
//  Plays with AVAudioPlayer (numberOfLoops = -1) in a .playback session (UIBackgroundModes=audio is in Info.plist).
//  Everything that matters for the test is written to Documents/bgm_<time>.csv.
//

import UIKit
import AVFoundation

final class BGMPlayer: NSObject, AVAudioPlayerDelegate {

    static let shared = BGMPlayer()
    static let resourceName = "bgm"
    static let extensions = ["caf", "m4a", "mp3", "wav", "aac"]
    static let fadeInSeconds: TimeInterval = 3
    static let autoStopSeconds: TimeInterval = 30 * 60

    // Settings (changeable while playing)
    var targetVolume: Float = 0.9 {
        didSet { if isRunning { player?.setVolume(targetVolume, fadeDuration: 0.2) } }
    }
    var continueOnSpeaker = false          // true: keep playing from the phone speaker when the AirPods come out
    var autoStop30 = false                 // true: stop by itself after 30 minutes

    // State shown on screen
    private(set) var isRunning = false
    private(set) var restartCount = 0
    private(set) var lastInterruption: Date?
    private(set) var startedAt: Date?
    private(set) var fileName = "-"
    var elapsed: TimeInterval { startedAt.map { Date().timeIntervalSince($0) } ?? 0 }

    var onChange: (() -> Void)?
    var onLog: ((String) -> Void)?

    private var player: AVAudioPlayer?
    private var logger: TTLogger?
    private var tick: Timer?
    private var interrupted = false

    // MARK: - Control

    @discardableResult
    func start() -> Bool {
        guard !isRunning else { return true }
        guard let url = bundledSong() else {
            fileName = "(no bgm file in the app)"
            onLog?("no bgm.* file found in the app bundle")
            onChange?()
            return false
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.numberOfLoops = -1
            p.volume = 0
            p.prepareToPlay()
            player = p
        } catch {
            onLog?("setup failed: \(error.localizedDescription)")
            return false
        }
        fileName = url.lastPathComponent
        logger = TTLogger(name: "bgm_\(TTFiles.stamp()).csv", header: "wall_iso,wall_epoch,uptime_s,elapsed_s,restarts,event,route")
        restartCount = 0
        interrupted = false
        startedAt = Date()
        isRunning = true
        observe()
        let ok = player?.play() ?? false
        player?.setVolume(targetVolume, fadeDuration: Self.fadeInSeconds)      // fade in from 0
        log("start file=\(fileName) play=\(ok) targetVolume=\(String(format: "%.2f", targetVolume)) fade=\(Int(Self.fadeInSeconds))s continueOnSpeaker=\(continueOnSpeaker) autoStop30=\(autoStop30)")
        tick = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.heartbeat() }
        onChange?()
        return ok
    }

    func stop(reason: String) {
        guard isRunning else { return }
        isRunning = false
        tick?.invalidate()
        tick = nil
        player?.stop()
        player = nil
        NotificationCenter.default.removeObserver(self)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        log("stop: \(reason)")
        logger?.close()
        logger = nil
        onChange?()
    }

    private func bundledSong() -> URL? {
        for ext in Self.extensions {
            if let u = Bundle.main.url(forResource: Self.resourceName, withExtension: ext) { return u }
        }
        return nil
    }

    // MARK: - Watchdog

    private func heartbeat() {
        guard isRunning else { return }
        if autoStop30 && elapsed >= Self.autoStopSeconds {
            stop(reason: "30-minute auto stop")
            return
        }
        if !interrupted, let p = player, !p.isPlaying {
            let ok = p.play()
            restartCount += 1
            log("unexpected stop detected -> play() returned \(ok) (restart #\(restartCount))")
        }
        onChange?()
    }

    // MARK: - Observers

    private func observe() {
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(interruption(_:)), name: AVAudioSession.interruptionNotification, object: nil)
        nc.addObserver(self, selector: #selector(routeChanged(_:)), name: AVAudioSession.routeChangeNotification, object: nil)
        nc.addObserver(self, selector: #selector(didEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        nc.addObserver(self, selector: #selector(willEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    @objc private func didEnterBackground() { log("app did enter background") }
    @objc private func willEnterForeground() { log("app will enter foreground") }

    @objc private func interruption(_ n: Notification) {
        let typeRaw = (n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) ?? 0
        let optRaw = (n.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt) ?? 0
        let shouldResume = AVAudioSession.InterruptionOptions(rawValue: optRaw).contains(.shouldResume)
        switch AVAudioSession.InterruptionType(rawValue: typeRaw) {
        case .began:
            interrupted = true
            lastInterruption = Date()
            log("interruption began")
        case .ended:
            interrupted = false
            lastInterruption = Date()
            var ok = false
            do {
                try AVAudioSession.sharedInstance().setActive(true)
                ok = player?.play() ?? false
            } catch {
                log("interruption ended: setActive failed: \(error.localizedDescription)")
            }
            if ok { restartCount += 1 }
            log("interruption ended shouldResume=\(shouldResume) -> resume success=\(ok)")
        default:
            break
        }
        onChange?()
    }

    @objc private func routeChanged(_ n: Notification) {
        let raw = (n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) ?? 0
        let reason = AVAudioSession.RouteChangeReason(rawValue: raw)
        let previous = (n.userInfo?[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription)?
            .outputs.map { $0.portName }.joined(separator: ", ") ?? "-"
        log("route change reason=\(Self.name(of: reason)) previous=[\(previous)] now=[\(TTAudio.routeDescription())]")
        guard isRunning, reason == .oldDeviceUnavailable else { return }

        if continueOnSpeaker {
            // Give iOS a moment to settle; if it paused the player, start it again on the new (speaker) route.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self = self, self.isRunning, let p = self.player else { return }
                if p.isPlaying {
                    self.log("action: output device removed -> keep playing on speaker (still playing, no restart needed)")
                } else {
                    let ok = p.play()
                    self.restartCount += 1
                    self.log("action: output device removed -> player had paused, play() returned \(ok) (restart #\(self.restartCount))")
                }
                self.onChange?()
            }
        } else {
            stop(reason: "output device removed (setting: stop)")
        }
    }

    private static func name(of r: AVAudioSession.RouteChangeReason?) -> String {
        switch r {
        case .newDeviceAvailable: return "newDeviceAvailable"
        case .oldDeviceUnavailable: return "oldDeviceUnavailable"
        case .categoryChange: return "categoryChange"
        case .override: return "override"
        case .wakeFromSleep: return "wakeFromSleep"
        case .noSuitableRouteForCategory: return "noSuitableRouteForCategory"
        case .routeConfigurationChange: return "routeConfigurationChange"
        default: return "unknown"
        }
    }

    // MARK: - AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        log("audioPlayerDidFinishPlaying successfully=\(flag) (should not happen while looping)")
        guard isRunning, !interrupted else { return }
        let ok = player.play()
        restartCount += 1
        log("restarted after finish: play() returned \(ok) (restart #\(restartCount))")
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        log("decode error: \(error?.localizedDescription ?? "unknown")")
    }

    // MARK: - Log

    private func log(_ event: String) {
        let clean = event.replacingOccurrences(of: "\"", with: "'")
        let route = TTAudio.routeDescription().replacingOccurrences(of: "\"", with: "'")
        logger?.write("\(TTClock.isoNow()),\(TTClock.epochNow()),\(TTClock.uptimeNow()),\(String(format: "%.1f", elapsed)),\(restartCount),\"\(clean)\",\"\(route)\"")
        let line = "\(TTClock.isoNow().suffix(13)) \(clean)"
        if Thread.isMainThread { onLog?(line) } else { DispatchQueue.main.async { [weak self] in self?.onLog?(line) } }
    }
}
