//
//  TopViewController.swift
//  AirPodsProMotion
//
//  Created by Yoshio on 2020/10/02.
//

import UIKit

class TopViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    
    private lazy var table: UITableView = {
        let table = UITableView(frame: self.view.bounds, style: .plain)
        table.autoresizingMask = [
          .flexibleWidth,
          .flexibleHeight
        ]
        table.rowHeight = 60
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()
    private var items: [() -> UIViewController] = [
        { BackgroundTestViewController() },
        { StretchTestViewController() },
        { AlertTestViewController() },
        {
            if #available(iOS 26.1, *) { return AlarmKitAlertViewController() }
            let v = UIViewController(); v.view.backgroundColor = .systemBackground; return v
        },
        { BGMTestViewController() },
        { StretchGuideViewController() },
        {
            // second-stage alert simulation: BGM starts, the guide opens, "완료" stops the BGM
            BGMPlayer.shared.start()
            return StretchGuideViewController(simulation: true, onDone: { BGMPlayer.shared.stop(reason: "완료 button") })
        }
    ]
    private var itemTitle: [String] = [
        "Test A: Background sensor",
        "Test B: Stretch matching",
        "Test C: Alert sound",
        "1차 알람 (AlarmKit)",
        "Test E: BGM 재생",
        "Test F: 스트레칭 가이드",
        "2차 알림 시뮬레이션"
    ]


    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.title = "TechTest"
        
        table.dataSource = self
        table.delegate = self
        view.addSubview(table)

    }
    
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return items.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: "cell")
        cell.textLabel?.text = itemTitle[indexPath.row]
        return cell
    }
    
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        self.navigationController?.pushViewController(items[indexPath.row](), animated: true)
    }

}
