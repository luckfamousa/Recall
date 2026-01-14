# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Recall is a macOS menu bar app for saving and restoring window layouts. It captures window positions using the Accessibility API and can restore them later, launching missing applications as needed.

## Tech Stack

- **Language**: Swift
- **Framework**: AppKit (not SwiftUI - AppKit is required for window control via Accessibility API)
- **Target**: macOS 13+
- **UI**: Menu bar only (LSUIElement app, no dock icon)

## Build Commands

```bash
# Build (debug)
swift build

# Build .app bundle (release, signed)
./Scripts/build-app.sh

# Install to /Applications
cp -r .build/Recall.app /Applications/

# Run directly (debug)
swift run
```

## Project Structure

```
Sources/Recall/
├── main.swift              # App entry point
├── AppDelegate.swift       # NSApplicationDelegate, coordinates components
├── Models/
│   └── Layout.swift        # Codable data model (Layout, DisplaySnapshot, WindowSnapshot)
├── Services/
│   ├── WindowManager.swift     # AX-based window capture/restore
│   ├── LayoutStorage.swift     # JSON file persistence
│   └── LoginItemManager.swift  # SMAppService wrapper
└── UI/
    └── MenuBarController.swift # NSStatusBar menu management
```

## Architecture

### Core Components

1. **Window Snapshot Engine** - Enumerates running applications via `NSWorkspace.shared.runningApplications` and their windows via Accessibility API (`AXUIElementCreateApplication`, `kAXWindowsAttribute`, etc.)

2. **Restore Engine** - Matches saved windows by bundle ID and title, launches missing apps via `NSWorkspace`, polls for windows to appear, then sets position/size via AX

3. **Menu Bar UI** - `NSStatusBar` based menu with layout list, save action, and login item toggle

4. **Auto-Start** - Uses `SMAppService.mainApp.register()` (Service Management API) for login item support

### Data Storage

Layouts are stored as JSON files in `~/Library/Application Support/<AppName>/layouts/`. Schema includes display UUIDs (not resolutions) to handle monitor changes.

### Required Permissions

- **Accessibility (AX)** - Required for reading/writing window positions
- No Screen Recording or Full Disk Access needed

## Key Implementation Notes

- Filter apps by `activationPolicy == .regular` and not hidden
- Use display UUID from `NSScreen.deviceDescription["NSScreenNumber"]` for multi-monitor support
- Window matching priority: bundle ID → window role → title substring
- Ignore transient windows (dialogs, popovers)
- Exponential backoff when waiting for windows during restore
- App launches use `.withoutActivation` option to avoid focus stealing
