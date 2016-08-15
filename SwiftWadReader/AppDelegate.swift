//
//  AppDelegate.swift
//  SwiftWadReader
//
//  Created by Benedikt Terhechte on 15/07/16.
//  Copyright © 2016 Benedikt Terhechte. All rights reserved.
//

import Cocoa

extension URL {
    static let WadFileURL = URL(string: "http://distro.ibiblio.org/slitaz/sources/packages/d/doom1.wad")!
}

struct Keys {
    private init() {}
    static var ProgressFractionCompleted = "fractionCompleted"
    static var ProgressLocalizedDescription = "localizedDescription"
    
    static var AppDelegateLockedUI = "lockedUI"
    static var AppDelegateLoadedUI = "loadedUI"
    
    static var UserDefaultsWadFileURL = "WadFileURL"
}

enum UIState {
    case unloaded
    case loading
    case parsing
    case loaded
}

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    @IBOutlet weak var window: NSWindow!
    @IBOutlet weak var progressBar: NSProgressIndicator!
    @IBOutlet weak var progressLabel: NSTextField!
    @IBOutlet weak var tableView: NSTableView!

    dynamic lazy var progress = Progress(totalUnitCount: 0)
    dynamic var lockedUI: Bool {
        return state == .loading || state == .parsing
    }
    
    dynamic var loadedUI: Bool {
        return state == .loaded
    }
    
    private var state: UIState = .unloaded {
        // We could also define KVO dependencies, but then using enums would be a bit more difficult
        willSet {
            willChangeValue(forKey: Keys.AppDelegateLockedUI)
            willChangeValue(forKey: Keys.AppDelegateLoadedUI)
        }
        didSet {
            didChangeValue(forKey: Keys.AppDelegateLoadedUI)
            didChangeValue(forKey: Keys.AppDelegateLockedUI)
        }
    }
    
    private var lumps: [Lump] = []

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        progress.kind = ProgressKind.file
        
        // If we already downloaded an wad file earlier, open it
        if let wadURL = UserDefaults.standard.url(forKey: Keys.UserDefaultsWadFileURL) {
            handleWADFile(url: wadURL)
        }
    }

    override func observeValue(forKeyPath keyPath: String?, of object: AnyObject?, change: [NSKeyValueChangeKey : AnyObject]?, context: UnsafeMutablePointer<Void>?) {
        switch context {
        case (&Keys.ProgressFractionCompleted)?:
            progressBar.doubleValue = progress.fractionCompleted
        case (&Keys.ProgressLocalizedDescription)?:
            progressLabel.stringValue = progress.localizedDescription
        default:
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }
    
    // MARK: Wad Parsing
    
    func handleWADFile(url wad: URL) {
        state = .parsing
        do {
            let wadReader = try WadReader(wadFile: wad)
            lumps = try wadReader.parse()
            state = .loaded
            
            tableView.reloadData()
            
        } catch let error as WadReaderError {
            switch error {
            case .invalidLup(reason: let reason):
                userError(withMessage: reason)
            case .invalidWadFile(reason: let reason):
                userError(withMessage: reason)
            }
        } catch let error {
            userError(withMessage: "\(error)")
        }
    }

    private func handleProgressEvent(object: AnyObject?, keyPath: String?, change: [NSKeyValueChangeKey : AnyObject]?) -> () {
        progressBar.doubleValue = progress.fractionCompleted
        progressLabel.stringValue = progress.localizedDescription
    }
    
    private func userError(withMessage message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = "There was an error"
        alert.beginSheetModal(for: self.window, completionHandler: nil)
    }

}

// MARK: UI

extension AppDelegate {
    @IBAction func downloadWadFile(sender: AnyObject) {
        
        state = .loading
        
        progress.addObserver(self, forKeyPath: Keys.ProgressFractionCompleted, options: [], context: &Keys.ProgressFractionCompleted)
        progress.addObserver(self, forKeyPath: Keys.ProgressLocalizedDescription, options: [], context: &Keys.ProgressLocalizedDescription)
        
        let session = URLSession(configuration: URLSessionConfiguration.ephemeral, delegate: self, delegateQueue: OperationQueue.main)
        
        session.downloadTask(with: URL.WadFileURL).resume()
    }
    
    @IBAction func openWadFile(sender: AnyObject) {
        let dialog = NSOpenPanel()
        dialog.allowedFileTypes = ["wad"]
        dialog.beginSheetModal(for: self.window, completionHandler: { (result: Int) -> Void in
            guard result == NSFileHandlingPanelOKButton,
                let url = dialog.url,
                FileManager.default.fileExists(atPath: url.path)
                else { return }
            
            self.handleWADFile(url: url)
            
            if self.state == .loaded {
                // store the successful location
                UserDefaults.standard.set(url, forKey: Keys.UserDefaultsWadFileURL)
            }

        })
    }
}

// MARK: TableView

extension AppDelegate: NSTableViewDataSource {
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> AnyObject? {
        return lumps[row].name
    }
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return lumps.count
    }
}

// MARK: Networking

extension AppDelegate: URLSessionDownloadDelegate {
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            userError(withMessage: error.localizedDescription)
            state = .unloaded
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        progress.totalUnitCount = 0
        progress.completedUnitCount = 0
        progress.removeObserver(self, forKeyPath: Keys.ProgressLocalizedDescription)
        progress.removeObserver(self, forKeyPath: Keys.ProgressFractionCompleted)
        state = .loaded
        handleWADFile(url: location)
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        print(totalBytesWritten, totalBytesWritten)
        progress.totalUnitCount = totalBytesExpectedToWrite
        progress.completedUnitCount = totalBytesWritten
        
    }
}

