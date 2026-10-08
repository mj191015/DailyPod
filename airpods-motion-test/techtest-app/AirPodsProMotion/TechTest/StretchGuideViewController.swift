//
//  StretchGuideViewController.swift
//  Test F: stretch guide. An opaque head follows the AirPods; a translucent head shows the target posture.
//  Based on the idea of the sample's SK3DViewController (SceneKit, node.eulerAngles = (-pitch, -yaw, -roll)).
//
//  Flow: start -> "look straight ahead" 3 s countdown -> pitch, roll and yaw are all set to 0 at that moment
//        (AirPods sit at an angle in the ear, so the raw values are not 0 when you look straight ahead)
//        -> the target head follows StretchMission.keyframes -> done.
//  "Left/right flip" mirrors roll and yaw of YOUR head, to find out which feels natural.
//

import UIKit
import SceneKit
import CoreMotion

final class StretchGuideViewController: UIViewController, CMHeadphoneMotionManagerDelegate {

    private enum Phase { case idle, countdown(Int), running, finished }

    private let simulation: Bool
    private let onDone: (() -> Void)?

    private let motion = CMHeadphoneMotionManager()
    private var latest: (pitch: Double, roll: Double, yaw: Double)?
    private var zero = (pitch: 0.0, roll: 0.0, yaw: 0.0)      // straight-ahead reference (set on the first sample, again at mission start)
    private var phase: Phase = .idle
    private var missionStart = Date()
    private var tick: Timer?
    private var previousIdleTimer = false
    private var raw: (qx: Double, qy: Double, qz: Double, qw: Double, gx: Double, gy: Double, gz: Double)?
    private var logger: TTLogger?
    private var frame = 0
    private var recentering = false

    private let scnView = SCNView()
    private let userHead = StretchGuideViewController.makeFigure(skin: UIColor.systemTeal, feature: UIColor.black, opacity: 1.0)
    private let targetHead = StretchGuideViewController.makeFigure(skin: UIColor.systemOrange, feature: UIColor(red: 0.45, green: 0.2, blue: 0, alpha: 1), opacity: 0.4)

    private let stateLabel = UILabel()
    private let stepLabel = UILabel()
    private let progress = UIProgressView(progressViewStyle: .default)
    private let diffLabel = UILabel()
    private let mirrorSwitch = UISwitch()
    private var startButton: UIButton!

    init(simulation: Bool = false, onDone: (() -> Void)? = nil) {
        self.simulation = simulation
        self.onDone = onDone
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = simulation ? "2차 알림 시뮬레이션" : "Test F: 스트레칭 가이드"
        view.backgroundColor = .black
        motion.delegate = self
        logger = TTLogger(name: "stretchguide_\(TTFiles.stamp()).csv",
                          header: "wall_epoch,kind,phase,mission_t,pitch,roll,yaw,qx,qy,qz,qw,gx,gy,gz,zero_pitch,zero_roll,zero_yaw,user_pitch,user_roll,user_yaw,target_pitch,target_roll,target_yaw,recentering,mirror,note")
        buildScene()
        buildUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        previousIdleTimer = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true               // keep the screen on during the mission
        if motion.isDeviceMotionAvailable {
            motion.startDeviceMotionUpdates(to: .main) { [weak self] m, error in
                guard let self = self, let m = m, error == nil else { return }
                let a = (m.attitude.pitch, m.attitude.roll, m.attitude.yaw)
                if self.latest == nil { self.zero = a }                    // first sample: assume you are looking straight ahead
                self.latest = a
                self.raw = (m.attitude.quaternion.x, m.attitude.quaternion.y, m.attitude.quaternion.z, m.attitude.quaternion.w,
                            m.gravity.x, m.gravity.y, m.gravity.z)
            }
        } else {
            stateLabel.text = "이 기기에서는 헤드폰 센서를 쓸 수 없어요"
        }
        tick = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.update() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        UIApplication.shared.isIdleTimerDisabled = previousIdleTimer  // restore
        motion.stopDeviceMotionUpdates()
        tick?.invalidate()
        tick = nil
        logger?.close()
    }

    // MARK: - Scene

    /// A face seen from the front (eyes, nose, mouth, ears) on a pivot at the base of the neck, so tilting swings the head.
    private static func makeFigure(skin: UIColor, feature: UIColor, opacity: CGFloat) -> SCNNode {
        func material(_ c: UIColor) -> SCNMaterial {
            let m = SCNMaterial()
            m.diffuse.contents = c
            m.lightingModel = .blinn
            m.transparency = opacity
            return m
        }
        func part(_ g: SCNGeometry, _ c: UIColor, _ x: Float, _ y: Float, _ z: Float) -> SCNNode {
            g.firstMaterial = material(c)
            let n = SCNNode(geometry: g)
            n.position = SCNVector3(x, y, z)
            return n
        }
        let pivot = SCNNode()
        pivot.position = SCNVector3(0, -1.4, 0)                      // top of the neck
        let head = SCNNode()
        head.position = SCNVector3(0, 1.5, 0)
        pivot.addChildNode(head)

        let skull = part(SCNSphere(radius: 1.2), skin, 0, 0, 0)
        skull.scale = SCNVector3(0.92, 1.15, 0.95)                   // slightly taller than wide
        head.addChildNode(skull)
        head.addChildNode(part(SCNSphere(radius: 0.12), feature, -0.42, 0.25, 1.03))   // eyes
        head.addChildNode(part(SCNSphere(radius: 0.12), feature, 0.42, 0.25, 1.03))
        let nose = part(SCNCone(topRadius: 0, bottomRadius: 0.16, height: 0.35), skin, 0, -0.1, 1.25)
        nose.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)            // apex points forward
        head.addChildNode(nose)
        head.addChildNode(part(SCNBox(width: 0.7, height: 0.08, length: 0.06, chamferRadius: 0.03), feature, 0, -0.55, 1.03))  // mouth
        let leftEar = part(SCNSphere(radius: 0.22), skin, -1.1, 0, 0); leftEar.scale = SCNVector3(0.5, 1, 0.8)
        let rightEar = part(SCNSphere(radius: 0.22), skin, 1.1, 0, 0); rightEar.scale = SCNVector3(0.5, 1, 0.8)
        head.addChildNode(leftEar)
        head.addChildNode(rightEar)

        if opacity < 1 { pivot.enumerateHierarchy { n, _ in n.renderingOrder = 10 } }
        return pivot
    }

    /// Neck and shoulders: fixed reference so the head's tilt, nod and turn are easy to read.
    private static func makeBody() -> SCNNode {
        let body = SCNNode()
        let gray = UIColor(white: 0.55, alpha: 1)
        let neck = SCNNode(geometry: SCNCylinder(radius: 0.42, height: 1.2))
        neck.geometry?.firstMaterial?.diffuse.contents = gray
        neck.position = SCNVector3(0, -1.9, 0)
        let shoulders = SCNNode(geometry: SCNBox(width: 4.4, height: 0.7, length: 1.4, chamferRadius: 0.3))
        shoulders.geometry?.firstMaterial?.diffuse.contents = gray
        shoulders.position = SCNVector3(0, -2.8, 0)
        body.addChildNode(neck)
        body.addChildNode(shoulders)
        return body
    }

    private func buildScene() {
        scnView.translatesAutoresizingMaskIntoConstraints = false
        scnView.backgroundColor = .black
        scnView.allowsCameraControl = false
        scnView.antialiasingMode = .multisampling4X
        view.addSubview(scnView)

        let scene = SCNScene()
        scnView.scene = scene
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.position = SCNVector3(0, -0.8, 8.5)                 // straight in front of the face
        scene.rootNode.addChildNode(camera)

        let omni = SCNNode()
        omni.light = SCNLight()
        omni.light?.type = .omni
        omni.position = SCNVector3(0, 8, 10)
        scene.rootNode.addChildNode(omni)
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = UIColor.darkGray
        scene.rootNode.addChildNode(ambient)

        targetHead.scale = SCNVector3(1.06, 1.06, 1.06)               // slightly larger so it never z-fights with your head
        scene.rootNode.addChildNode(StretchGuideViewController.makeBody())
        scene.rootNode.addChildNode(userHead)
        scene.rootNode.addChildNode(targetHead)
    }

    // MARK: - UI

    private func buildUI() {
        func style(_ l: UILabel, _ size: CGFloat, _ weight: UIFont.Weight = .regular) {
            l.textColor = .white
            l.numberOfLines = 0
            l.textAlignment = .center
            l.font = .monospacedDigitSystemFont(ofSize: size, weight: weight)
        }
        style(stateLabel, 20, .semibold)
        style(stepLabel, 24, .bold)
        style(diffLabel, 14)
        stateLabel.text = "시작을 누르면 3초 뒤 시작해요"
        progress.progressTintColor = .systemOrange
        progress.trackTintColor = UIColor(white: 0.25, alpha: 1)

        let legend = UILabel()
        style(legend, 12)
        legend.text = "● 청록(불투명) = 내 머리   ● 주황(반투명) = 목표 자세"
        legend.textColor = UIColor(white: 0.8, alpha: 1)

        let mirrorLabel = UILabel()
        style(mirrorLabel, 13)
        mirrorLabel.text = "좌우 반전 (거울처럼)"
        mirrorLabel.textAlignment = .right
        let mirrorRow = UIStackView(arrangedSubviews: [mirrorLabel, mirrorSwitch])
        mirrorRow.spacing = 10
        mirrorRow.alignment = .center
        mirrorRow.distribution = .equalCentering

        startButton = TTUI.button("시작", target: self, action: #selector(startTapped))
        let recenter = TTUI.button("정면 맞추기 (지금 자세를 0으로)", target: self, action: #selector(recenterTapped))
        recenter.backgroundColor = .systemGray
        var rows: [UIView] = [stepLabel, progress, diffLabel, mirrorRow, recenter, startButton]
        if simulation {
            let done = TTUI.button("완료 (BGM 정지)", target: self, action: #selector(doneTapped))
            done.backgroundColor = .systemRed
            rows.append(done)
        }
        let bottom = UIStackView(arrangedSubviews: rows)
        bottom.axis = .vertical
        bottom.spacing = 10
        let top = UIStackView(arrangedSubviews: [stateLabel, legend])
        top.axis = .vertical
        top.spacing = 4
        top.translatesAutoresizingMaskIntoConstraints = false
        bottom.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(top)
        view.addSubview(bottom)

        let g = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo: g.topAnchor, constant: 8),
            top.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 16),
            top.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -16),
            bottom.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 16),
            bottom.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -16),
            bottom.bottomAnchor.constraint(equalTo: g.bottomAnchor, constant: -10),
            scnView.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 4),
            scnView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scnView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scnView.bottomAnchor.constraint(equalTo: bottom.topAnchor, constant: -6)
        ])
    }

    // MARK: - Mission

    @objc private func startTapped() {
        if case .countdown = phase { return }
        if case .running = phase { return }
        guard latest != nil else {
            stateLabel.text = "센서 값이 아직 안 들어와요. 에어팟을 착용했는지 확인하세요"
            return
        }
        beginCountdown(3)
    }

    private func beginCountdown(_ n: Int) {
        phase = .countdown(n)
        startButton.isEnabled = false
        startButton.alpha = 0.4
        stateLabel.text = "정면을 보세요  \(n)"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self = self, case .countdown = self.phase else { return }
            if n > 1 {
                self.beginCountdown(n - 1)
            } else {
                if let l = self.latest { self.zero = l }       // straight ahead = 0 on all three axes from now on
                self.missionStart = Date()
                self.phase = .running
                self.stateLabel.text = "\(StretchMission.name) 진행 중"
                self.logger?.write("\(TTClock.epochNow()),event,running,0.00,,,,,,,,,,,,,,,,,,,,,\(self.mirrorSwitch.isOn ? 1 : 0),mission start (zero set)")
            }
        }
    }

    private func finishMission() {
        phase = .finished
        stateLabel.text = "끝! (판정은 이번 범위가 아니에요)"
        startButton.isEnabled = true
        startButton.alpha = 1
        startButton.setTitle("다시 시작", for: .normal)
    }

    @objc private func recenterTapped() {
        if let l = latest { zero = l }
        logger?.write("\(TTClock.epochNow()),event,\(phaseName),\(String(format: "%.2f", missionTime)),,,,,,,,,,,,,,,,,,,,,\(mirrorSwitch.isOn),manual recenter button")
    }

    private var phaseName: String {
        switch phase { case .idle: return "idle"; case .countdown: return "countdown"; case .running: return "running"; case .finished: return "finished" }
    }

    private var missionTime: Double {
        if case .running = phase { return Date().timeIntervalSince(missionStart) }
        if case .finished = phase { return StretchMission.duration }
        return 0
    }

    /// Wrap an angle difference to -pi...pi.
    private func wrap(_ d: Double) -> Double {
        var x = d
        while x > Double.pi { x -= 2 * Double.pi }
        while x < -Double.pi { x += 2 * Double.pi }
        return x
    }

    /// During a neutral hold the screen slowly re-zeroes to the user's current posture, but only if they are already
    /// within 35 degrees of the current zero (so a stretch that is still being held is never "absorbed").
    private func autoRecenter(at t: Double) {
        guard case .running = phase, StretchMission.isRecenterWindow(at: t), let l = latest else { recentering = false; return }
        let limit = 35.0 * Double.pi / 180
        let dp = l.pitch - zero.pitch, dr = l.roll - zero.roll, dy = wrap(l.yaw - zero.yaw)
        guard abs(dp) < limit, abs(dr) < limit, abs(dy) < limit else { recentering = false; return }
        let k = 0.12                                              // about 0.3 s time constant at 30 fps
        zero = (zero.pitch + dp * k, zero.roll + dr * k, zero.yaw + dy * k)
        recentering = true
    }

    @objc private func doneTapped() {
        onDone?()
        navigationController?.popViewController(animated: true)
    }

    // MARK: - Per-frame update

    private func relativeYaw(_ yaw: Double) -> Double {
        var d = yaw - zero.yaw
        while d > Double.pi { d -= 2 * Double.pi }
        while d < -Double.pi { d += 2 * Double.pi }
        return d
    }

    private func update() {
        autoRecenter(at: missionTime)

        // user's head: all three axes relative to the straight-ahead reference; mirror flips roll and yaw
        var user = (pitch: 0.0, roll: 0.0, yaw: 0.0)
        if let l = latest {
            let m = mirrorSwitch.isOn ? -1.0 : 1.0
            user = (l.pitch - zero.pitch, (l.roll - zero.roll) * m, relativeYaw(l.yaw) * m)
        }
        userHead.eulerAngles = SCNVector3(Float(-user.pitch), Float(-user.yaw), Float(-user.roll))

        // target head
        var t = 0.0
        if case .running = phase {
            t = Date().timeIntervalSince(missionStart)
            if t >= StretchMission.duration { t = StretchMission.duration; finishMission() }
        } else if case .finished = phase {
            t = StretchMission.duration
        }
        let target = StretchMission.pose(at: t)
        targetHead.eulerAngles = SCNVector3(Float(-target.pitch), Float(-target.yaw), Float(-target.roll))

        // texts
        switch phase {
        case .running, .finished:
            stepLabel.text = StretchMission.stepText(at: t)
            progress.progress = Float(min(1, t / StretchMission.duration))
        default:
            stepLabel.text = StretchMission.name
            progress.progress = 0
        }
        let dp = (user.pitch - target.pitch) * 180 / .pi
        let dr = (user.roll - target.roll) * 180 / .pi
        let dy = (user.yaw - target.yaw) * 180 / .pi
        let total = (dp * dp + dr * dr + dy * dy).squareRoot()
        diffLabel.text = String(format: "목표와 차이  pitch %+.0f°  roll %+.0f°  yaw %+.0f°   (합 %.0f°)", dp, dr, dy, total)
        if case .running = phase { stateLabel.text = recentering ? "정면 자동 보정 중... 가만히 계세요" : "\(StretchMission.name) 진행 중" }

        frame += 1
        if frame % 3 == 0, let l = latest, let r = raw {                // about 10 rows per second
            switch phase {
            case .idle: break
            default:
                logger?.write("\(TTClock.epochNow()),sample,\(phaseName),\(String(format: "%.2f", t)),\(l.pitch),\(l.roll),\(l.yaw),\(r.qx),\(r.qy),\(r.qz),\(r.qw),\(r.gx),\(r.gy),\(r.gz),\(zero.pitch),\(zero.roll),\(zero.yaw),\(user.pitch),\(user.roll),\(user.yaw),\(target.pitch),\(target.roll),\(target.yaw),\(recentering ? 1 : 0),\(mirrorSwitch.isOn ? 1 : 0),")
            }
        }
    }
}
