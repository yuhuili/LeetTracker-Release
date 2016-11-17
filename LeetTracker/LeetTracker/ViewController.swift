//
//  ViewController.swift
//  LeetTracker
//
//  Created by Alexander Li on 2016-11-03.
//  Copyright © 2016 Yuhui Li. All rights reserved.
//

import Cocoa
import Kanna

class ViewController: NSViewController, NSTextFieldDelegate {

    @IBOutlet weak var statusLabel: NSTextField!
    @IBOutlet weak var tfGitRepo: NSTextField!
    @IBOutlet weak var tfDatabase: NSTextField!
    @IBOutlet weak var tfLCCookie: NSTextField!
    @IBOutlet weak var mainButton: NSButton!
    
    var gitRepoReady = false;
    var databaseReady = false;
    var lcAccountReady = false;
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        
        loadDefaults()
        validateStatus()
        checkStatus()
    }

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }
    
    func updateStatus(status: String?) {
        if let newStatus = status {
            statusLabel.stringValue = String(format: Constants.statusTextTemplate, newStatus)
        }
    }
    
    func loadDefaults() {
        let defaults = UserDefaults.standard
        if let gitRepoPath = defaults.object(forKey: "GitRepoPath") as? String {
            tfGitRepo.stringValue = gitRepoPath
        }
        if let databasePath = defaults.object(forKey: "DatabasePath") as? String {
            tfDatabase.stringValue = databasePath
        }
    }
    
    func validateStatus() {
        gitRepoReady = LTCore.sharedInstance.isValidGitRepo(path: tfGitRepo.stringValue)
        databaseReady = LTCore.sharedInstance.isValidDatabasePath(path: tfDatabase.stringValue)
    }
    
    func checkStatus() {
        let defaults = UserDefaults.standard
        
        if gitRepoReady && databaseReady && lcAccountReady {
            updateStatus(status: "Ready")
            mainButton.isEnabled = true
            mainButton.title = "Start"
        } else if !gitRepoReady && !databaseReady && !lcAccountReady  {
            updateStatus(status: "Waiting...")
            mainButton.isEnabled = false
        } else {
            var s = ""
            if gitRepoReady {
                s += "Git Repo "
                defaults.set(tfGitRepo.stringValue, forKey: "GitRepoPath")
            }
            if databaseReady {
                s += "Database "
                defaults.set(tfDatabase.stringValue, forKey: "DatabasePath")
            }
            if lcAccountReady {
                s += "Leet Code Account "
            }
            s += "Ready, waiting..."
            updateStatus(status: s)
            mainButton.isEnabled = false
        }
    }
    
    @IBAction func mainButtonPressed(_ sender: NSButton) {
        sender.isEnabled = false
        sender.stringValue = "Waiting..."
        
        LTCore.sharedInstance.startProcessing(gitrepo: tfGitRepo.stringValue, database: tfDatabase.stringValue) { (success, error) in
            print("completed")
        }
    }
    
    
    // MARK: NSTextFieldDelegate
    override func controlTextDidEndEditing(_ obj: Notification) {
        if obj.object as? NSTextField == tfGitRepo {
            gitRepoReady = LTCore.sharedInstance.isValidGitRepo(path: tfGitRepo.stringValue)
            checkStatus()
        } else if obj.object as? NSTextField == tfDatabase {
            databaseReady = LTCore.sharedInstance.isValidDatabasePath(path: tfDatabase.stringValue)
            checkStatus()
        } else if obj.object as? NSTextField == tfLCCookie {
            LTCore.sharedInstance.isValidLCAccount(cookie: tfLCCookie.stringValue, completion: {success in
                self.lcAccountReady = success
                self.checkStatus()
            })
        }
    }


}

