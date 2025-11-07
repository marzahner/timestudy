import SwiftUI
import AppKit
import Foundation
import Combine

@main
struct AutoScreenshotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var timer: Timer?
    var screenshotManager: ScreenshotManager!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        screenshotManager = ScreenshotManager()
        
        // Create menu bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "camera.circle", accessibilityDescription: "AutoScreenshot")
            button.action = #selector(togglePopover)
        }
        
        // Create popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 350, height: 580)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: SettingsView(manager: screenshotManager))
    }
    
    @objc func togglePopover() {
        if let button = statusItem.button {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }
}

enum ImageQuality: String, CaseIterable, Identifiable {
    case original = "Original"
    case high = "High (1920px)"
    case medium = "Medium (1280px)"
    case low = "Low (960px)"
    case veryLow = "Very Low (640px)"
    case minimal = "Minimal (480px)"
    
    var id: String { rawValue }
    
    var maxWidth: CGFloat? {
        switch self {
        case .original: return nil
        case .high: return 1920
        case .medium: return 1280
        case .low: return 960
        case .veryLow: return 640
        case .minimal: return 480
        }
    }
}

struct ScreenshotCapture {
    let image: NSImage
    let tempPath: String
    let timestamp: Date
}

class ScreenshotManager: ObservableObject {
    @Published var isRunning = false
    @Published var interval: Double = 300 // seconds
    @Published var saveDirectory: String = ""
    @Published var includeTimestamp = true
    @Published var captureSound = false
    @Published var screenshotCount = 0
    @Published var imageQuality: ImageQuality = .medium
    @Published var compressionQuality: Double = 0.7 // 0.0 to 1.0
    @Published var estimatedFileSize: String = "~500 KB"
    @Published var enableAnnotation = true
    @Published var presetAnnotation: String = ""
    @Published var usePresetAnnotation = false
    @Published var currentCapture: ScreenshotCapture?
    @Published var showAnnotationWindow = false
    
    private var timer: Timer?
    var annotationWindow: NSWindow?
    
    init() {
        // Load saved preferences
        loadPreferences()
        
        // Set default directory if none saved
        if saveDirectory.isEmpty {
            saveDirectory = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Screenshots/Auto").path
        }
        
        updateEstimatedFileSize()
    }
    
    func start() {
        guard !isRunning else { return }
        
        // Create directory if it doesn't exist
        createDirectoryIfNeeded()
        
        // Start timer
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.takeScreenshot()
        }
        
        isRunning = true
        savePreferences()
    }
    
    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        savePreferences()
    }
    
    func takeScreenshot() {
        // Create temporary path for full-quality screenshot
        let tempPath = NSTemporaryDirectory() + UUID().uuidString + "_screenshot.png"
        
        // Build screencapture command
        var arguments = ["-x"] // No sound by default
        if captureSound {
            arguments.removeAll(where: { $0 == "-x" })
        }
        arguments.append(tempPath)
        
        let task = Process()
        task.launchPath = "/usr/sbin/screencapture"
        task.arguments = arguments
        
        do {
            try task.run()
            task.waitUntilExit()
            
            if let image = NSImage(contentsOfFile: tempPath) {
                if enableAnnotation && !usePresetAnnotation {
                    // Show annotation window for manual input
                    DispatchQueue.main.async {
                        self.currentCapture = ScreenshotCapture(
                            image: image,
                            tempPath: tempPath,
                            timestamp: Date()
                        )
                        self.showAnnotationWindow = true
                        self.presentAnnotationWindow()
                    }
                } else if usePresetAnnotation && !presetAnnotation.isEmpty {
                    // Use preset annotation automatically
                    processAndSave(image: image, tempPath: tempPath, annotation: presetAnnotation)
                } else {
                    // Save directly without annotation
                    processAndSave(image: image, tempPath: tempPath, annotation: nil)
                }
            }
            
        } catch {
            print("Error taking screenshot: \(error)")
        }
    }
    
    func presentAnnotationWindow() {
        guard let capture = currentCapture else { return }
        
        let annotationView = AnnotationView(
            image: capture.image,
            onSave: { [weak self] annotation in
                self?.processAndSave(image: capture.image, tempPath: capture.tempPath, annotation: annotation)
                self?.closeAnnotationWindow()
            },
            onSkip: { [weak self] in
                self?.processAndSave(image: capture.image, tempPath: capture.tempPath, annotation: nil)
                self?.closeAnnotationWindow()
            }
        )
        
        let hostingController = NSHostingController(rootView: annotationView)
        
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Add Note to Screenshot"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 600, height: 500))
        window.center()
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        annotationWindow = window
    }
    
    func closeAnnotationWindow() {
        annotationWindow?.close()
        annotationWindow = nil
        showAnnotationWindow = false
        currentCapture = nil
    }
    
    func processAndSave(image: NSImage, tempPath: String, annotation: String?) {
        // Process the image with optional annotation overlay
        var finalImage = image
        
        if let text = annotation, !text.isEmpty {
            finalImage = addAnnotationToImage(image: image, text: text)
        }
        
        // Process and compress the image
        if let processedImage = processImage(finalImage) {
            let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
                .replacingOccurrences(of: " ", with: "_")
            
            let filename = includeTimestamp ? "screenshot_\(timestamp).jpg" : "screenshot_\(screenshotCount).jpg"
            let savePath = (saveDirectory as NSString).appendingPathComponent(filename)
            
            // Save compressed image as JPEG
            if let jpegData = processedImage.jpegData(compressionQuality: compressionQuality) {
                try? jpegData.write(to: URL(fileURLWithPath: savePath))
                
                DispatchQueue.main.async {
                    self.screenshotCount += 1
                    self.savePreferences()
                }
            }
        }
        
        // Clean up temp file
        try? FileManager.default.removeItem(atPath: tempPath)
    }
    
    private func addAnnotationToImage(image: NSImage, text: String) -> NSImage {
        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData) else {
            return image
        }
        
        let width = CGFloat(bitmapRep.pixelsWide)
        let height = CGFloat(bitmapRep.pixelsHigh)
        
        // Create new bitmap representation
        guard let annotatedBitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(width),
            pixelsHigh: Int(height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return image
        }
        
        // Draw into the new bitmap context
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: annotatedBitmap)
        NSGraphicsContext.current = context
        
        // Draw original image
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        
        // Calculate sizes
        let padding: CGFloat = 20
        let fontSize = max(width * 0.018, 16)
        let maxTextWidth = width - (padding * 4)
        
        // Create attributed string
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left
        paragraphStyle.lineBreakMode = .byWordWrapping
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraphStyle
        ]
        
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedString.boundingRect(
            with: NSSize(width: maxTextWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).size
        
        // Create background
        let boxHeight = textSize.height + (padding * 1.5)
        let boxWidth = min(textSize.width + (padding * 2), width - (padding * 2))
        let boxX = padding
        let boxY = height - boxHeight - padding
        
        let boxRect = NSRect(x: boxX, y: boxY, width: boxWidth, height: boxHeight)
        let path = NSBezierPath(roundedRect: boxRect, xRadius: 12, yRadius: 12)
        
        NSColor.black.withAlphaComponent(0.75).setFill()
        path.fill()
        
        NSColor.white.withAlphaComponent(0.2).setStroke()
        path.lineWidth = 1.5
        path.stroke()
        
        // Draw text
        let textRect = NSRect(
            x: boxX + padding,
            y: boxY + (padding * 0.75),
            width: maxTextWidth,
            height: textSize.height
        )
        attributedString.draw(in: textRect)
        
        NSGraphicsContext.restoreGraphicsState()
        
        // Create final image
        let newImage = NSImage(size: NSSize(width: width, height: height))
        newImage.addRepresentation(annotatedBitmap)
        
        return newImage
    }
    
    private func processImage(_ image: NSImage) -> NSImage? {
        // Get original size from the image's bitmap representation
        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData) else {
            return image
        }
        
        let originalWidth = CGFloat(bitmapRep.pixelsWide)
        let originalHeight = CGFloat(bitmapRep.pixelsHigh)
        
        // Calculate new size if resizing is needed
        var newWidth = originalWidth
        var newHeight = originalHeight
        
        if let maxWidth = imageQuality.maxWidth, originalWidth > maxWidth {
            let ratio = maxWidth / originalWidth
            newWidth = maxWidth
            newHeight = originalHeight * ratio
        }
        
        // If no resize needed and original quality, return as is
        if newWidth == originalWidth && imageQuality == .original {
            return image
        }
        
        // Create new bitmap representation with exact pixel dimensions
        guard let resizedBitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(newWidth),
            pixelsHigh: Int(newHeight),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return image
        }
        
        // Draw into the new bitmap context
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: resizedBitmap)
        NSGraphicsContext.current = context
        
        image.draw(
            in: NSRect(x: 0, y: 0, width: newWidth, height: newHeight),
            from: NSRect(x: 0, y: 0, width: originalWidth, height: originalHeight),
            operation: .copy,
            fraction: 1.0
        )
        
        NSGraphicsContext.restoreGraphicsState()
        
        // Create final image from bitmap
        let resizedImage = NSImage(size: NSSize(width: newWidth, height: newHeight))
        resizedImage.addRepresentation(resizedBitmap)
        
        return resizedImage
    }
    
    func updateInterval(_ newInterval: Double) {
        let wasRunning = isRunning
        if wasRunning {
            stop()
        }
        
        interval = newInterval
        savePreferences()
        
        if wasRunning {
            start()
        }
    }
    
    func updateEstimatedFileSize() {
        // Rough estimation based on quality and compression
        let baseSize: Double = {
            switch imageQuality {
            case .original: return 3000 // ~3MB
            case .high: return 1500     // ~1.5MB
            case .medium: return 800    // ~800KB
            case .low: return 400       // ~400KB
            case .veryLow: return 200   // ~200KB
            case .minimal: return 100   // ~100KB
            }
        }()
        
        let compressedSize = baseSize * compressionQuality
        
        if compressedSize < 1024 {
            estimatedFileSize = "~\(Int(compressedSize)) KB"
        } else {
            estimatedFileSize = String(format: "~%.1f MB", compressedSize / 1024)
        }
    }
    
    private func createDirectoryIfNeeded() {
        let url = URL(fileURLWithPath: saveDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    
    func savePreferences() {
        UserDefaults.standard.set(interval, forKey: "interval")
        UserDefaults.standard.set(saveDirectory, forKey: "saveDirectory")
        UserDefaults.standard.set(includeTimestamp, forKey: "includeTimestamp")
        UserDefaults.standard.set(captureSound, forKey: "captureSound")
        UserDefaults.standard.set(screenshotCount, forKey: "screenshotCount")
        UserDefaults.standard.set(isRunning, forKey: "isRunning")
        UserDefaults.standard.set(imageQuality.rawValue, forKey: "imageQuality")
        UserDefaults.standard.set(compressionQuality, forKey: "compressionQuality")
        UserDefaults.standard.set(enableAnnotation, forKey: "enableAnnotation")
        UserDefaults.standard.set(presetAnnotation, forKey: "presetAnnotation")
        UserDefaults.standard.set(usePresetAnnotation, forKey: "usePresetAnnotation")
    }
    
    private func loadPreferences() {
        interval = UserDefaults.standard.double(forKey: "interval")
        if interval == 0 { interval = 300 }
        
        saveDirectory = UserDefaults.standard.string(forKey: "saveDirectory") ?? ""
        includeTimestamp = UserDefaults.standard.bool(forKey: "includeTimestamp")
        captureSound = UserDefaults.standard.bool(forKey: "captureSound")
        screenshotCount = UserDefaults.standard.integer(forKey: "screenshotCount")
        compressionQuality = UserDefaults.standard.double(forKey: "compressionQuality")
        if compressionQuality == 0 { compressionQuality = 0.7 }
        
        enableAnnotation = UserDefaults.standard.object(forKey: "enableAnnotation") as? Bool ?? true
        presetAnnotation = UserDefaults.standard.string(forKey: "presetAnnotation") ?? ""
        usePresetAnnotation = UserDefaults.standard.bool(forKey: "usePresetAnnotation")
        
        if let qualityString = UserDefaults.standard.string(forKey: "imageQuality"),
           let quality = ImageQuality(rawValue: qualityString) {
            imageQuality = quality
        }
        
        // Auto-resume if it was running
        if UserDefaults.standard.bool(forKey: "isRunning") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.start()
            }
        }
    }
}

extension NSImage {
    func jpegData(compressionQuality: Double) -> Data? {
        guard let tiffData = self.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        
        return bitmapImage.representation(
            using: .jpeg,
            properties: [.compressionFactor: compressionQuality]
        )
    }
}

struct AnnotationView: View {
    let image: NSImage
    let onSave: (String) -> Void
    let onSkip: () -> Void
    
    @State private var annotation = ""
    @State private var nsImage: NSImage?
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Preview
            GeometryReader { geometry in
                ScrollView([.horizontal, .vertical]) {
                    if let img = nsImage {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.9))
            }
            
            // Annotation Input Area
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "text.bubble")
                        .foregroundColor(.blue)
                    Text("Add a note (1-2 sentences)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                TextEditor(text: $annotation)
                    .frame(height: 60)
                    .padding(8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    .focused($isTextFieldFocused)
                
                HStack(spacing: 12) {
                    Button("Skip") {
                        onSkip()
                    }
                    .keyboardShortcut(.escape, modifiers: [])
                    .buttonStyle(BorderedButtonStyle())
                    
                    Spacer()
                    
                    Button("Save") {
                        onSave(annotation.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .buttonStyle(BorderedProminentButtonStyle())
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            .frame(height: 160)
        }
        .onAppear {
            nsImage = image
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTextFieldFocused = true
            }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var manager: ScreenshotManager
    @State private var showingFolderPicker = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                HStack {
                    Image(systemName: "camera.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.blue)
                    
                    VStack(alignment: .leading) {
                        Text("AutoScreenshot")
                            .font(.title2)
                            .bold()
                        Text("\(manager.screenshotCount) screenshots taken")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top)
                
                Divider()
                
                // Play/Pause Button
                Button(action: {
                    if manager.isRunning {
                        manager.stop()
                    } else {
                        manager.start()
                    }
                }) {
                    HStack {
                        Image(systemName: manager.isRunning ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 24))
                        Text(manager.isRunning ? "Pause" : "Start")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(manager.isRunning ? Color.orange : Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .buttonStyle(PlainButtonStyle())
                
                // Settings
                VStack(alignment: .leading, spacing: 15) {
                    Text("Settings")
                        .font(.headline)
                    
                    // Interval Selector
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Interval: \(formatInterval(manager.interval))")
                            .font(.subheadline)
                        
                        Picker("", selection: Binding(
                            get: { manager.interval },
                            set: { manager.updateInterval($0) }
                        )) {
                            Text("30 seconds").tag(30.0)
                            Text("1 minute").tag(60.0)
                            Text("5 minutes").tag(300.0)
                            Text("10 minutes").tag(600.0)
                            Text("15 minutes").tag(900.0)
                            Text("20 minutes").tag(1200.0)
                            Text("30 minutes").tag(1800.0)
                            Text("1 hour").tag(3600.0)
                        }
                        .pickerStyle(MenuPickerStyle())
                    }
                    
                    // Save Directory
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Save Location")
                            .font(.subheadline)
                        
                        HStack {
                            Text(manager.saveDirectory)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            
                            Spacer()
                            
                            Button("Choose...") {
                                selectFolder()
                            }
                            .buttonStyle(BorderedButtonStyle())
                        }
                    }
                    
                    Divider()
                    
                    // Annotation Settings
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Annotations")
                            .font(.subheadline)
                            .bold()
                        
                        Toggle("Enable annotation prompts", isOn: $manager.enableAnnotation)
                            .font(.subheadline)
                            .onChange(of: manager.enableAnnotation) {
                                if manager.enableAnnotation {
                                    manager.usePresetAnnotation = false
                                }
                                manager.savePreferences()
                            }
                        
                        if manager.enableAnnotation {
                            HStack {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.blue)
                                    .font(.caption)
                                Text("A window will appear after each screenshot to add notes")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(8)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(6)
                        }
                        
                        Toggle("Use preset annotation", isOn: $manager.usePresetAnnotation)
                            .font(.subheadline)
                            .onChange(of: manager.usePresetAnnotation) {
                                if manager.usePresetAnnotation {
                                    manager.enableAnnotation = false
                                }
                                manager.savePreferences()
                            }
                        
                        if manager.usePresetAnnotation {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Preset text (applied to all screenshots)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                TextEditor(text: $manager.presetAnnotation)
                                    .frame(height: 60)
                                    .padding(8)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                    )
                                    .onChange(of: manager.presetAnnotation) {
                                        manager.savePreferences()
                                    }
                            }
                            
                            HStack {
                                Image(systemName: "checkmark.circle")
                                    .foregroundColor(.green)
                                    .font(.caption)
                                Text("This text will be automatically added to all screenshots")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(8)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(6)
                        }
                    }
                    
                    Divider()
                    
                    // Image Quality Settings
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Image Quality")
                            .font(.subheadline)
                            .bold()
                        
                        Picker("Resolution", selection: $manager.imageQuality) {
                            ForEach(ImageQuality.allCases) { quality in
                                Text(quality.rawValue).tag(quality)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .onChange(of: manager.imageQuality) {
                            manager.updateEstimatedFileSize()
                            manager.savePreferences()
                        }
                        
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text("Compression")
                                    .font(.caption)
                                Spacer()
                                Text("\(Int(manager.compressionQuality * 100))%")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Slider(value: $manager.compressionQuality, in: 0.1...1.0, step: 0.1)
                                .onChange(of: manager.compressionQuality) {
                                    manager.updateEstimatedFileSize()
                                    manager.savePreferences()
                                }
                            
                            HStack {
                                Text("Smaller")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("Better Quality")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        HStack {
                            Image(systemName: "doc.fill")
                                .foregroundColor(.blue)
                            Text("Est. file size: \(manager.estimatedFileSize)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(8)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(6)
                    }
                    
                    Divider()
                    
                    // Options
                    Toggle("Include timestamp in filename", isOn: $manager.includeTimestamp)
                        .font(.subheadline)
                        .onChange(of: manager.includeTimestamp) {
                            manager.savePreferences()
                        }
                    
                    Toggle("Play camera sound", isOn: $manager.captureSound)
                        .font(.subheadline)
                        .onChange(of: manager.captureSound) {
                            manager.savePreferences()
                        }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
                
                // Quit Button
                Button("Quit AutoScreenshot") {
                    NSApplication.shared.terminate(nil)
                }
                .foregroundColor(.red)
                .font(.caption)
                .padding(.bottom)
            }
            .padding()
        }
        .frame(width: 350, height: 580)
    }
    
    func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                manager.saveDirectory = url.path
                manager.savePreferences()
            }
        }
    }
    
    func formatInterval(_ seconds: Double) -> String {
        if seconds < 60 {
            return "\(Int(seconds)) seconds"
        } else if seconds < 3600 {
            return "\(Int(seconds / 60)) minutes"
        } else {
            return "\(Int(seconds / 3600)) hour\(seconds >= 7200 ? "s" : "")"
        }
    }
}
