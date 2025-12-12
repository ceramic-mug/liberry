import Flutter
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, UIDocumentPickerDelegate {
    
    var pendingResult: FlutterResult?
    var activeSecurityScopedURL: URL?  // Track the URL we're accessing
    
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        
        let controller = window?.rootViewController as! FlutterViewController
        let channel = FlutterMethodChannel(name: "com.liberry.app/sync", binaryMessenger: controller.binaryMessenger)
        
        channel.setMethodCallHandler { [weak self] (call, result) in
            guard let self = self else { return }
            
            switch call.method {
            case "pickSyncFile":
                self.pickSyncFile(result: result)
                
            case "prepareSyncRead":
                if let bookmarkBase64 = call.arguments as? String {
                    self.prepareSyncRead(bookmarkBase64: bookmarkBase64, result: result)
                } else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Bookmark required", details: nil))
                }
                
            case "commitSyncWrite":
                if let args = call.arguments as? [String: String],
                   let bookmarkBase64 = args["bookmark"],
                   let tempPath = args["tempPath"] {
                    self.commitSyncWrite(bookmarkBase64: bookmarkBase64, tempPath: tempPath, result: result)
                } else {
                    result(FlutterError(code: "INVALID_ARGS", message: "bookmark and tempPath required", details: nil))
                }
                
            case "cleanupSync":
                if let tempPath = call.arguments as? String {
                    self.cleanupSync(tempPath: tempPath, result: result)
                } else {
                    result(nil)
                }
                
            case "stopAccess":
                self.stopAccess(result: result)
                
            default:
                result(FlutterMethodNotImplemented)
            }
        }
        
        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    // MARK: - File Picker
    
    func pickSyncFile(result: @escaping FlutterResult) {
        let types: [UTType] = [.data, .database, .item]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        
        self.pendingResult = result
        
        DispatchQueue.main.async {
            if let controller = self.window?.rootViewController {
                controller.present(picker, animated: true, completion: nil)
            } else {
                result(FlutterError(code: "NO_ROOT_VC", message: "Cannot find root view controller", details: nil))
                self.pendingResult = nil
            }
        }
    }
    
    // MARK: - UIDocumentPickerDelegate
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else {
            self.pendingResult?(nil)
            self.pendingResult = nil
            return
        }
        
        print("Document picker returned URL: \(url)")
        print("URL path: \(url.path)")
        print("URL is file URL: \(url.isFileURL)")
        
        // Start accessing to generate bookmark
        let canAccess = url.startAccessingSecurityScopedResource()
        print("startAccessingSecurityScopedResource returned: \(canAccess)")
        
        // Check if file exists
        let fileManager = FileManager.default
        var exists = fileManager.fileExists(atPath: url.path)
        print("File exists at path (initial): \(exists)")
        
        // If file doesn't exist, it might be a cloud file that needs to be downloaded
        // Use NSFileCoordinator to trigger download
        if !exists {
            print("File not downloaded, attempting coordinated access to trigger download...")
            
            let coordinator = NSFileCoordinator(filePresenter: nil)
            var coordinatorError: NSError?
            
            // This will trigger the file provider to download the file
            coordinator.coordinate(readingItemAt: url, options: [], error: &coordinatorError) { accessedURL in
                exists = fileManager.fileExists(atPath: accessedURL.path)
                print("After coordination, file exists: \(exists)")
                
                if exists {
                    self.createBookmark(for: accessedURL, canAccess: canAccess)
                } else {
                    print("File still does not exist after coordination")
                    self.pendingResult?(FlutterError(code: "FILE_NOT_DOWNLOADED", message: "The file could not be downloaded from the cloud. Please ensure the file is available offline.", details: nil))
                    self.pendingResult = nil
                }
            }
            
            if let error = coordinatorError {
                print("Coordinator error: \(error)")
                self.pendingResult?(FlutterError(code: "COORDINATOR_ERROR", message: error.localizedDescription, details: nil))
                self.pendingResult = nil
            }
            
            if canAccess {
                url.stopAccessingSecurityScopedResource()
            }
        } else {
            createBookmark(for: url, canAccess: canAccess)
        }
    }
    
    private func createBookmark(for url: URL, canAccess: Bool) {
        defer {
            if canAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        do {
            // Use empty options for iOS - security scope is implicit
            let bookmarkData = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            let bookmarkBase64 = bookmarkData.base64EncodedString()
            
            print("Successfully created bookmark")
            self.pendingResult?(["path": url.path, "bookmark": bookmarkBase64])
        } catch {
            print("Error creating bookmark: \(error)")
            self.pendingResult?(FlutterError(code: "BOOKMARK_ERROR", message: error.localizedDescription, details: nil))
        }
        
        self.pendingResult = nil
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        self.pendingResult?(nil)
        self.pendingResult = nil
    }
    
    // MARK: - Coordinated File Operations
    
    /// Resolves bookmark, copies cloud file to temp location using NSFileCoordinator
    func prepareSyncRead(bookmarkBase64: String, result: @escaping FlutterResult) {
        guard let bookmarkData = Data(base64Encoded: bookmarkBase64) else {
            result(FlutterError(code: "INVALID_BASE64", message: "Invalid bookmark data", details: nil))
            return
        }
        
        var isStale = false
        let url: URL
        do {
            url = try URL(resolvingBookmarkData: bookmarkData, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
        } catch {
            result(FlutterError(code: "RESOLVE_ERROR", message: error.localizedDescription, details: nil))
            return
        }
        
        if isStale {
            result(FlutterError(code: "BOOKMARK_STALE", message: "Bookmark is stale. Please re-select the sync file.", details: nil))
            return
        }
        
        guard url.startAccessingSecurityScopedResource() else {
            result(FlutterError(code: "ACCESS_DENIED", message: "Could not access security scoped resource", details: nil))
            return
        }
        
        // Store the URL so we can stop access later
        self.activeSecurityScopedURL = url
        
        // Create temp file path
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("sync_working_copy.db")
        
        // Delete old temp file if exists
        try? FileManager.default.removeItem(at: tempFile)
        
        // Use NSFileCoordinator for reading
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinatorError: NSError?
        
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinatorError) { readURL in
            do {
                try FileManager.default.copyItem(at: readURL, to: tempFile)
                result(tempFile.path)
            } catch {
                result(FlutterError(code: "COPY_ERROR", message: "Failed to copy file: \(error.localizedDescription)", details: nil))
            }
        }
        
        if let error = coordinatorError {
            result(FlutterError(code: "COORDINATOR_ERROR", message: "File coordination failed: \(error.localizedDescription)", details: nil))
        }
    }
    
    /// Copies temp file back to cloud location using NSFileCoordinator
    func commitSyncWrite(bookmarkBase64: String, tempPath: String, result: @escaping FlutterResult) {
        guard let bookmarkData = Data(base64Encoded: bookmarkBase64) else {
            result(FlutterError(code: "INVALID_BASE64", message: "Invalid bookmark data", details: nil))
            return
        }
        
        var isStale = false
        let cloudURL: URL
        do {
            cloudURL = try URL(resolvingBookmarkData: bookmarkData, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
        } catch {
            result(FlutterError(code: "RESOLVE_ERROR", message: error.localizedDescription, details: nil))
            return
        }
        
        // If we don't already have access, start it
        if self.activeSecurityScopedURL?.path != cloudURL.path {
            guard cloudURL.startAccessingSecurityScopedResource() else {
                result(FlutterError(code: "ACCESS_DENIED", message: "Could not access security scoped resource for writing", details: nil))
                return
            }
            self.activeSecurityScopedURL = cloudURL
        }
        
        let tempFileURL = URL(fileURLWithPath: tempPath)
        
        // Use NSFileCoordinator for writing
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinatorError: NSError?
        
        coordinator.coordinate(writingItemAt: cloudURL, options: .forReplacing, error: &coordinatorError) { writeURL in
            do {
                // Remove destination first if it exists (required for copy to work)
                if FileManager.default.fileExists(atPath: writeURL.path) {
                    try FileManager.default.removeItem(at: writeURL)
                }
                try FileManager.default.copyItem(at: tempFileURL, to: writeURL)
                result(true)
            } catch {
                result(FlutterError(code: "WRITE_ERROR", message: "Failed to write file: \(error.localizedDescription)", details: nil))
            }
        }
        
        if let error = coordinatorError {
            result(FlutterError(code: "COORDINATOR_ERROR", message: "File coordination failed: \(error.localizedDescription)", details: nil))
        }
    }
    
    /// Cleans up temp file
    func cleanupSync(tempPath: String, result: @escaping FlutterResult) {
        let tempURL = URL(fileURLWithPath: tempPath)
        try? FileManager.default.removeItem(at: tempURL)
        result(nil)
    }
    
    /// Stops accessing the security scoped resource
    func stopAccess(result: @escaping FlutterResult) {
        if let url = self.activeSecurityScopedURL {
            url.stopAccessingSecurityScopedResource()
            self.activeSecurityScopedURL = nil
            print("Stopped accessing security scoped resource: \(url.path)")
        }
        result(nil)
    }
}

