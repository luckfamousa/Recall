# Recall

A macOS menu bar app for saving and restoring window layouts.

## Features

- **Save window layouts** - Capture positions and sizes of all open windows
- **Restore layouts** - Return windows to their saved positions with one click
- **Multi-monitor support** - Handles windows across multiple displays
- **Smart window matching** - Matches windows even when titles change dynamically
- **Auto-launch apps** - Launches closed apps and reopens windows when restoring
- **Edit layouts** - Open layout files in your default JSON editor
- **Start at login** - Optional automatic startup

## Requirements

- macOS 13.0 or later
- Accessibility permission (prompted on first use)

## Installation

### Build from source

```bash
# Clone the repository
git clone https://github.com/yourusername/recall.git
cd recall

# Build and create app bundle
./Scripts/build-app.sh

# Install to Applications (recommended)
cp -r Recall.app /Applications/
```

### Grant permissions

On first run, Recall will request Accessibility permission. Grant access in:

**System Settings > Privacy & Security > Accessibility**

## Usage

Recall lives in your menu bar with a window grid icon.

### Save a layout

1. Arrange your windows as desired
2. Click the menu bar icon
3. Select **Save Current Layout...**
4. Enter a name and click Save

### Restore a layout

1. Click the menu bar icon
2. Hover over **Restore**
3. Select the layout to restore

### Manage layouts

- **Delete** - Remove saved layouts
- **Edit** - Open layout JSON in your default editor

Layouts are stored in `~/Library/Application Support/Recall/layouts/`

## How it works

Recall uses the macOS Accessibility API to:
- Enumerate windows from running applications
- Read window positions and sizes
- Move and resize windows during restore

Window matching uses multiple strategies:
1. Exact title match
2. Stable title match (ignores dynamic suffixes)
3. Partial title match
4. Window index fallback

## Development

### Project structure

```
Recall/
├── Package.swift
├── Sources/Recall/
│   ├── main.swift
│   ├── AppDelegate.swift
│   ├── Models/
│   │   └── Layout.swift
│   ├── Services/
│   │   ├── WindowManager.swift
│   │   ├── LayoutStorage.swift
│   │   └── LoginItemManager.swift
│   └── UI/
│       └── MenuBarController.swift
├── Resources/
│   └── Info.plist
└── Scripts/
    ├── build-app.sh
    └── update-app.sh
```

### Build commands

```bash
# Debug build
swift build

# Release build
swift build -c release

# Create app bundle
./Scripts/build-app.sh

# Update binary only (preserves TCC authorization)
./Scripts/update-app.sh
```

### Debug logging

Debug logs are written to `~/recall_debug.log`

```bash
# Watch logs in real-time
tail -f ~/recall_debug.log
```

## License

MIT
