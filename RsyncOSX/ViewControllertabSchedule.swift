//
//  ViewControllertabSchedule.swift
//  RsyncOSXver30
//
//  Created by Thomas Evensen on 19/08/2016.
//  Copyright © 2016 Thomas Evensen. All rights reserved.
//
//  swiftlint:disable line_length

import Foundation
import Cocoa

// Protocol for restarting timer
protocol StartTimer : class {
    func startTimerNextJob()
}

class ViewControllertabSchedule: NSViewController {

    weak var configurationsDelegate: GetConfigurationsObject?
    var configurations: Configurations?
    weak var schedulesDelegate: GetSchedulesObject?
    var schedules: Schedules?

    // Main tableview
    @IBOutlet weak var mainTableView: NSTableView!
    @IBOutlet weak var once: NSButton!
    @IBOutlet weak var daily: NSButton!
    @IBOutlet weak var weekly: NSButton!
    @IBOutlet weak var details: NSButton!

    private var index: Int?
    private var hiddenID: Int?
    private var newSchedules: Bool?
    private var nextTask: Timer?
    private var schedulessorted: ScheduleSortedAndExpand?
    weak var startnextjobDelegate: StartNextScheduledTask?

    // Information Schedule details
    // self.presentViewControllerAsSheet(self.ViewControllerScheduleDetails)
    lazy var viewControllerScheduleDetails: NSViewController = {
        return (self.storyboard!.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier(rawValue: "StoryboardScheduleID"))
            as? NSViewController)!
    }()

    // Userconfiguration
    // self.presentViewControllerAsSheet(self.ViewControllerUserconfiguration)
    lazy var viewControllerUserconfiguration: NSViewController = {
        return (self.storyboard!.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier(rawValue: "StoryboardUserconfigID"))
            as? NSViewController)!
    }()

    @IBOutlet weak var firstScheduledTask: NSTextField!
    @IBOutlet weak var secondScheduledTask: NSTextField!
    @IBOutlet weak var firstRemoteServer: NSTextField!
    @IBOutlet weak var secondRemoteServer: NSTextField!
    @IBOutlet weak var firstLocalCatalog: NSTextField!
    @IBOutlet weak var secondLocalCatalog: NSTextField!

    @IBAction func chooseSchedule(_ sender: NSButton) {

        let startdate: Date = Date()
        // Seconds from now to starttime
        let seconds: TimeInterval = self.stoptime.dateValue.timeIntervalSinceNow
        // Date and time for stop
        let stopdate: Date = self.stopdate.dateValue.addingTimeInterval(seconds)
        let secondsstart: TimeInterval = self.stopdate.dateValue.timeIntervalSinceNow
        var schedule: String?
        var details: Bool = false
        var range: Bool = false

        if self.index != nil {
            if self.once.state == .on {
                schedule = "once"
                if seconds > 0 {
                    range = true
                } else {
                    self.info(str: "Startdate has passed...")
                }
            } else if self.daily.state  == .on {
                schedule = "daily"
                if secondsstart >= (60*60*24) {
                    range = true
                } else {
                    self.info(str: "Startdate has to be more than 24 hours ahead...")
                }
            } else if self.weekly.state  == .on {
                schedule = "weekly"
                if secondsstart >= (60*60*24*7) {
                    range = true
                } else {
                    self.info(str: "Startdate has to be more than 7 days ahead...")
                }
            } else if self.details.state  == .on {
                // Details
                details = true
                globalMainQueue.async(execute: { () -> Void in
                     self.presentViewControllerAsSheet(self.viewControllerScheduleDetails)
                })
                self.details.state = .off
            }
            if details == false && range == true {
                self.addschedule(schedule: schedule!, startdate: startdate, stopdate: stopdate)
            }
            // Reset radiobuttons
            self.once.state = .off
            self.daily.state = .off
            self.weekly.state = .off
            self.details.state = .off
        }
    }

    private func addschedule(schedule: String, startdate: Date, stopdate: Date) {
        let answer = Alerts.dialogOKCancel("Add Schedule?", text: "Cancel or OK")
        if answer {
            self.schedules!.addschedule(self.hiddenID!, schedule: schedule, start: startdate, stop: stopdate)
            self.newSchedules = true
            // Refresh table and recalculate the Schedules jobs
            self.reload()
            // Start next job, if any, by delegate
            self.startnextjobDelegate = ViewControllerReference.shared.getvcref(viewcontroller: .vctabmain) as? ViewControllertabMain
            self.startnextjobDelegate?.startanyscheduledtask()
            // Displaying next two scheduled tasks
            self.nextScheduledtask()
            // Call function to check if a scheduled backup is due for countdown
            self.startTimer()
        }
    }

    private func info(str: String) {
        self.firstLocalCatalog.textColor = .red
        self.firstLocalCatalog.stringValue = str
    }

    // Userconfiguration button
    @IBAction func userconfiguration(_ sender: NSButton) {
        globalMainQueue.async(execute: { () -> Void in
            self.presentViewControllerAsSheet(self.viewControllerUserconfiguration)
        })
    }

    // Date for stopping services
    @IBOutlet weak var stopdate: NSDatePicker!
    // Time for stopping services
    @IBOutlet weak var stoptime: NSDatePicker!

    // Initial functions viewDidLoad and viewDidAppear
    override func viewDidLoad() {
        super.viewDidLoad()
        self.newSchedules = false
        self.mainTableView.delegate = self
        self.mainTableView.dataSource = self
        self.schedulessorted = ScheduleSortedAndExpand()
        // Setting reference to self.
        ViewControllerReference.shared.setvcref(viewcontroller: .vctabschedule, nsviewcontroller: self)
        self.configurationsDelegate = ViewControllerReference.shared.getvcref(viewcontroller: .vctabmain)
            as? ViewControllertabMain
        self.schedulesDelegate = ViewControllerReference.shared.getvcref(viewcontroller: .vctabmain)
            as? ViewControllertabMain
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        self.configurations = self.configurationsDelegate?.getconfigurationsobject()
        self.schedules = self.schedulesDelegate?.getschedulesobject()
        self.stopdate.dateValue = Date()
        self.stoptime.dateValue = Date()
        if self.schedulessorted == nil {
            self.schedulessorted = ScheduleSortedAndExpand()
        }
        if self.configurations!.configurationsDataSourcecountBackupOnlyCount() > 0 {
            globalMainQueue.async(execute: { () -> Void in
                self.mainTableView.reloadData()
            })
        }
        // Displaying next two scheduled tasks
        self.nextScheduledtask()
        // Call function to check if a scheduled backup is due for countdown
        self.startTimer()
    }

    // Start timer
    func startTimer() {
        if self.schedulessorted != nil {
            let timer: Double = self.schedulessorted!.startTimerseconds()
            // timer == 0 do not start NSTimer, timer > 0 update frequens of NSTimer
            if timer > 0 {
                self.nextTask?.invalidate()
                self.nextTask = nil
                // Update when next task is to be executed
                self.nextTask = Timer.scheduledTimer(timeInterval: timer, target: self, selector: #selector(nextScheduledtask), userInfo: nil, repeats: true)
            }
        }
    }

    // Update display next scheduled jobs in time
    @objc func nextScheduledtask() {
        guard self.schedulessorted != nil else {
            return
        }
        // Displaying next two scheduled tasks
        self.firstLocalCatalog.textColor = .black
        self.firstScheduledTask.stringValue = self.schedulessorted!.whenIsNextTwoTasksString()[0]
        self.secondScheduledTask.stringValue = self.schedulessorted!.whenIsNextTwoTasksString()[1]
        if self.schedulessorted!.remoteServerAndPathNextTwoTasks().count > 0 {
            if self.schedulessorted!.remoteServerAndPathNextTwoTasks().count > 2 {
                self.firstRemoteServer.stringValue = self.schedulessorted!.remoteServerAndPathNextTwoTasks()[0]
                self.firstLocalCatalog.stringValue = self.schedulessorted!.remoteServerAndPathNextTwoTasks()[1]
                self.secondRemoteServer.stringValue = self.schedulessorted!.remoteServerAndPathNextTwoTasks()[2]
                self.secondLocalCatalog.stringValue = self.schedulessorted!.remoteServerAndPathNextTwoTasks()[3]
            } else {
                guard self.schedulessorted!.remoteServerAndPathNextTwoTasks().count == 2 else {
                    return
                }
                self.firstRemoteServer.stringValue = self.schedulessorted!.remoteServerAndPathNextTwoTasks()[0]
                self.firstLocalCatalog.stringValue = self.schedulessorted!.remoteServerAndPathNextTwoTasks()[1]
                self.secondRemoteServer.stringValue = ""
                self.secondLocalCatalog.stringValue = ""
            }
        }
    }

    // setting which table row is selected
    func tableViewSelectionDidChange(_ notification: Notification) {
        let myTableViewFromNotification = (notification.object as? NSTableView)!
        let indexes = myTableViewFromNotification.selectedRowIndexes
        if let index = indexes.first {
            // Set index
            self.index = index
            let dict = self.configurations!.getConfigurationsDataSourcecountBackupOnly()![index]
            self.hiddenID = dict.value(forKey: "hiddenID") as? Int
        } else {
            self.index = nil
            self.hiddenID = nil
        }
    }

}

extension ViewControllertabSchedule : NSTableViewDataSource {

    func numberOfRows(in tableView: NSTableView) -> Int {
        guard self.configurations != nil else {
            return 0
        }
        return self.configurations!.configurationsDataSourcecountBackupOnlyCount()
    }
}

extension ViewControllertabSchedule : NSTableViewDelegate {

    @objc(tableView:objectValueForTableColumn:row:) func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        let object: NSDictionary = self.configurations!.getConfigurationsDataSourcecountBackupOnly()![row]
        var text: String?
        var schedule: Bool = false
        var number: Int?

        let hiddenID: Int = (object.value(forKey: "hiddenID") as? Int)!
        if self.schedules!.hiddenIDinSchedule(hiddenID) {
            text = object[tableColumn!.identifier] as? String
            if text == "backup" || text == "restore" {
                schedule = true
            }
        }
        if tableColumn!.identifier.rawValue == "batchCellID" {
            return object[tableColumn!.identifier] as? Int!
        } else {
            if self.schedulessorted != nil {
                number = self.schedulessorted!.numberOfFutureSchedules(hiddenID)
            } else {
                number = 0
            }
            if schedule && number! > 0 {
                let returnstr = text! + " (" + String(number!) + ")"
                return returnstr
            } else {
                return object[tableColumn!.identifier] as? String
            }
        }
    }

    // Toggling batch
    @objc(tableView:setObjectValue:forTableColumn:row:) func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
        if self.configurations!.getConfigurations()[row].task == "backup" {
            self.configurations!.getConfigurationsDataSource()![row].setObject(object!, forKey: (tableColumn?.identifier)! as NSCopying)
            self.configurations!.setBatchYesNo(row)
        }
    }

}

extension  ViewControllertabSchedule: GetHiddenID {

    func gethiddenID() -> Int {
        return self.hiddenID!
    }

}

extension ViewControllertabSchedule: DismissViewController {

    func dismiss_view(viewcontroller: NSViewController) {
        self.dismissViewController(viewcontroller)
    }
}

extension ViewControllertabSchedule: AddProfiles {

    // Just reset the schedules
    func newProfile(profile: String?) {
        self.schedulessorted = nil
        self.firstRemoteServer.stringValue = ""
        self.firstLocalCatalog.stringValue = ""
        self.secondRemoteServer.stringValue = ""
        self.secondLocalCatalog.stringValue = ""
    }

    func enableProfileMenu() {
        // Nothing, just for complying to protocol
    }

}

extension ViewControllertabSchedule: Reloadandrefresh {

    func reload() {
        if self.configurations!.configurationsDataSourcecountBackupOnlyCount() > 0 {
            globalMainQueue.async(execute: { () -> Void in
                self.mainTableView.reloadData()
            })
        }
        self.firstRemoteServer.stringValue = ""
        self.firstLocalCatalog.stringValue = ""
        self.secondRemoteServer.stringValue = ""
        self.secondLocalCatalog.stringValue = ""
        // Create a New schedules object
        self.schedulessorted = nil
        self.schedulessorted = ScheduleSortedAndExpand()
        // Displaying next two scheduled tasks
        self.firstScheduledTask.stringValue = self.schedulessorted!.whenIsNextTwoTasksString()[0]
        self.secondScheduledTask.stringValue = self.schedulessorted!.whenIsNextTwoTasksString()[1]
    }

}

extension ViewControllertabSchedule: StartTimer {

    // Called from Process
    func startTimerNextJob() {
        self.schedulessorted = nil
        self.schedulessorted = ScheduleSortedAndExpand()
        self.firstRemoteServer.stringValue = ""
        self.firstLocalCatalog.stringValue = ""
        self.startTimer()
    }
}
