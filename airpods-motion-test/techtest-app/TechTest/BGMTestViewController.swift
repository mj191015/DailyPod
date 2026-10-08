//
//  BGMTestViewController.swift
//  Test E: does loud BGM keep looping without breaks (screen on / Home / locked)?
//

import UIKit

final class BGMTestViewController: UIViewController {

    private let bgm = BGMPlayer.shared
    private let elapsedLabel = TTUI.label("", size: 22, mono: true)
    private let routeLabel = TTUI.label("", size: 13)
    private let interruptionLabel = TTUI.label("", size: 13)
    private let restartLabel = TTUI.label("", size: 13)
    private let fileLabel = TTUI.label("", size: 12)
    private let volumeLabel = TTUI.label("", size: 14)
    private let slider = UISlider()
    private let speakerSwitch = UISwitch()
    private let timerSwitch = UISwitch()
    private var startButton: UIButton!
    private let logView = TTUI.logView()
    private var refreshTimer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Test E: BGM"
        view.backgroundColor = .systemBackground

        slider.minimumValue = 0.1
        slider.maximumValue = 1.0
        slider.value = bgm.targetVolume
        slider.addTarget(self, action: #selector(volumeChanged), for: .valueChanged)
        speakerSwitch.isOn = bgm.continueOnSpeaker
        speakerSwitch.addTarget(self, action: #selector(speakerChanged), for: .valueChanged)
        timerSwitch.isOn = bgm.autoStop30
        timerSwitch.addTarget(self, action: #selector(timerChanged), for: .valueChanged)
        startButton = TTUI.button("시작", target: self, action: #selector(toggle))

        TTUI.stack(in: self, [
            startButton, elapsedLabel, routeLabel, interruptionLabel, restartLabel, fileLabel,
            volumeLabel, slider,
            row("에어팟이 빠지면: 폰 스피커로 계속 (끄면 멈춤)", speakerSwitch),
            row("30분 타이머 자동 정지", timerSwitch),
            logView
        ])
        volumeChanged()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        bgm.onChange = { [weak self] in self?.refresh() }
        bgm.onLog = { [weak self] line in
            guard let self = self else { return }
            TTUI.appendLog(self.logView, line)
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.refresh() }
        refresh()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        bgm.onChange = nil
        bgm.onLog = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func row(_ text: String, _ sw: UISwitch) -> UIView {
        let l = TTUI.label(text, size: 14)
        let s = UIStackView(arrangedSubviews: [l, sw])
        s.axis = .horizontal
        s.spacing = 8
        s.alignment = .center
        return s
    }

    // MARK: - Actions

    @objc private func toggle() {
        if bgm.isRunning { bgm.stop(reason: "stop button") } else { bgm.start() }
        refresh()
    }

    @objc private func volumeChanged() {
        bgm.targetVolume = slider.value
        volumeLabel.text = String(format: "목표 볼륨 %.0f%% (시작할 때 3초 동안 0에서 서서히 올라감)", slider.value * 100)
    }

    @objc private func speakerChanged() { bgm.continueOnSpeaker = speakerSwitch.isOn }
    @objc private func timerChanged() { bgm.autoStop30 = timerSwitch.isOn }

    private func refresh() {
        let e = Int(bgm.elapsed)
        elapsedLabel.text = bgm.isRunning
            ? String(format: "재생 중  %02d:%02d", e / 60, e % 60)
            : "멈춤" + (bgm.startedAt != nil ? String(format: "  (마지막 %02d:%02d)", e / 60, e % 60) : "")
        routeLabel.text = "출력: \(TTAudio.routeDescription())"
        if let t = bgm.lastInterruption {
            let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
            interruptionLabel.text = "마지막 인터럽션: \(f.string(from: t))"
        } else {
            interruptionLabel.text = "마지막 인터럽션: 없음"
        }
        restartLabel.text = "재시작 횟수: \(bgm.restartCount)"
        fileLabel.text = "음원: \(bgm.fileName)"
        startButton.setTitle(bgm.isRunning ? "정지" : "시작", for: .normal)
        startButton.backgroundColor = bgm.isRunning ? .systemRed : .systemBlue
    }
}
