# AutoScreenshot

A native macOS menu bar app that automatically captures screenshots at regular intervals with optional annotations, compression, and custom quality settings.

![macOS](https://img.shields.io/badge/macOS-14.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Features

### 🎯 Core Functionality
- **Menu bar integration** - Quick access from anywhere
- **Automated intervals** - 30 seconds to 1 hour intervals
- **Play/Pause control** - Easy start/stop
- **Auto-resume** - Continues capturing after app restart

### 📝 Annotation Options
- **Manual annotations** - Popup prompts for custom notes per screenshot
- **Preset annotations** - Set once, apply to all screenshots automatically
- **Stylish overlays** - Professional semi-transparent text boxes on images
- **Skip option** - Press ESC to save without annotation

### 🖼️ Image Quality Control
- **Resolution options**
  - Original (full resolution)
  - High (1920px)
  - Medium (1280px)
  - Low (960px)
  - Very Low (640px)
  - Minimal (480px)
- **Compression slider** - 10% to 100% JPEG quality
- **File size estimation** - Real-time preview of output size
- **Actual pixel-accurate resizing** - True dimensions, not retina-scaled

### ⚙️ Customization
- **Configurable save location** - Choose any folder
- **Timestamp filenames** - Optional date/time in filename
- **Camera sound toggle** - Enable/disable capture sound
- **Persistent settings** - All preferences saved automatically

## Installation

### Requirements
- macOS 14.0 or later
- Xcode 15.0 or later (for building)
- Apple Silicon (M1/M2/M3) or Intel Mac

### Building from Source

1. **Clone or download** the project
2. **Open in Xcode**
   ```bash
   open AutoScreenshot.xcodeproj
   ```

3. **Select your development team**
   - Select project in sidebar
   - Go to "Signing & Capabilities"
   - Choose your Apple ID/team from dropdown

4. **Build and run**
   - Press ⌘+R or click Run button
   - App appears in menu bar (camera icon)

**Note:** App Sandbox is already disabled in the project to allow file system access.

## Usage

### Quick Start

1. **Click camera icon** in menu bar
2. **Choose save location** with "Choose..." button
3. **Select interval** (e.g., 5 minutes)
4. **Configure quality settings** (optional)
5. **Press Start** button

### Annotation Modes

#### Manual Annotations
1. Enable "Enable annotation prompts"
2. After each screenshot, a window appears
3. Type 1-2 sentences
4. Press `Cmd+Enter` to save or `ESC` to skip

#### Preset Annotations
1. Enable "Use preset annotation"
2. Enter text in preset field (e.g., "Working on project X")
3. Press Start
4. Text automatically applied to all screenshots - no interruptions!

#### No Annotations
- Disable both toggles
- Screenshots saved immediately without any text overlay

### Keyboard Shortcuts

**In annotation window:**
- `Cmd + Enter` - Save with annotation
- `ESC` - Skip annotation

### Settings Overview

**Intervals:**
- 30 seconds
- 1 minute
- 5 minutes
- 10 minutes
- 15 minutes
- 20 minutes
- 30 minutes
- 1 hour

**Image Quality:**
- Choose resolution (Original to 480px)
- Adjust compression (10-100%)
- View estimated file size

**File Sizes (approximate):**
- Original + 100%: ~3 MB
- Medium (1280px) + 70%: ~500 KB
- Minimal (480px) + 30%: ~30-50 KB

## How It Works

### Screenshot Process

1. **Capture** - Uses macOS native `screencapture` command
2. **Annotation** - Optionally adds text overlay with styled background
3. **Resize** - Scales to selected resolution using bitmap rendering
4. **Compress** - Converts to JPEG with chosen quality
5. **Save** - Writes to your specified folder

### Technical Details

- **SwiftUI** - Modern native macOS UI
- **Bitmap rendering** - Pixel-accurate resizing (not retina-scaled)
- **JPEG compression** - Efficient file sizes
- **Timer-based** - Reliable interval triggering
- **UserDefaults** - Settings persistence

## File Structure

```
AutoScreenshot/
├── AutoScreenshotApp.swift    # Main app code
├── Info.plist                 # App configuration
└── Assets.xcassets/           # App icons
```

## Troubleshooting

### Screenshots not saving to chosen folder
**Solution:** Disable App Sandbox
- Project settings → Signing & Capabilities
- Remove "App Sandbox" capability

### Image dimensions wrong (doubled)
**Fixed in latest version** - Now uses bitmap-based rendering for accurate pixel dimensions

### Layout recursion warning
**Fixed in latest version** - Improved annotation window layout

### Task name port warning
**Solution:** Disable App Sandbox (see above)

## Configuration Files

Settings stored in `UserDefaults`:
- Interval
- Save directory
- Image quality
- Compression level
- Annotation preferences
- Screenshot count

## Performance

- **Minimal CPU usage** when idle
- **Low memory footprint** (~50-100 MB)
- **No background processes** when paused
- **Efficient JPEG compression** reduces disk usage

## Use Cases

- **Time-lapse projects** - Document progress over hours/days
- **Productivity tracking** - Visual log of work sessions
- **Tutorial creation** - Capture step-by-step workflows
- **Client reporting** - Show project development
- **Personal diary** - Visual timeline with notes
- **Focus sessions** - Automatic documentation without interruption

## Roadmap

Potential future features:
- [ ] Multiple display selection
- [ ] Cloud sync integration
- [ ] Screenshot preview thumbnails
- [ ] Custom keyboard shortcuts
- [ ] Export as video/GIF
- [ ] Scheduled start/stop times

## Privacy

- **No data collection** - Everything stored locally
- **No network access** - Fully offline
- **User-controlled** - You choose where files are saved
- **No telemetry** - No analytics or tracking

## License

MIT License - Feel free to modify and distribute

## Credits

Built with Swift and SwiftUI for macOS

## Support

For issues or questions, check the troubleshooting section or review the code comments.

---

**Tip:** For long recording sessions, use lower quality settings (640px + 50% compression) to save disk space while maintaining readability.