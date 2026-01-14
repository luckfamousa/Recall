Below is a concrete, engineering-grade implementation plan for a minimal macOS layout-snapshot app, explicitly including automatic start after boot.
This is scoped to stay small, understandable, and robust.

⸻

Implementation Plan — Layout Snapshot & Restore App

Scope (non-negotiable)
	•	Snapshot current window layout
	•	Restore layout exactly
	•	Launch missing apps automatically
	•	Menu-bar only (no dock icon)
	•	Auto-start after boot
	•	No tiling, no snapping, no rules engine

⸻

Phase 0 — Technology & Constraints

Language & Framework
	•	Swift
	•	AppKit (not SwiftUI for window control)
	•	Target: macOS 13+

Required Permissions
	•	Accessibility (AX)
	•	No Screen Recording required
	•	No Full Disk Access

⸻

Phase 1 — Core Data Model

Layout Schema (v1)

Human-readable, versioned JSON.

{
  "version": 1,
  "name": "Work",
  "created_at": "2026-01-14T09:30:00Z",
  "displays": [
    {
      "display_uuid": "37D8832A-2D66-02CA-B9F7-8F30A301B230",
      "windows": [
        {
          "bundle_id": "com.apple.Safari",
          "window_title": "Firemetrics",
          "role": "AXWindow",
          "frame": { "x": 120, "y": 40, "w": 1680, "h": 980 }
        }
      ]
    }
  ]
}

Storage
	•	~/Library/Application Support/<AppName>/layouts/
	•	One file per layout

⸻

Phase 2 — Window Snapshot Engine

Enumerate Applications
	•	NSWorkspace.shared.runningApplications
	•	Filter:
	•	activationPolicy == .regular
	•	not hidden

Enumerate Windows (AX)

For each app:
	1.	AXUIElementCreateApplication(pid)
	2.	Read:
	•	kAXWindowsAttribute
	•	kAXTitleAttribute
	•	kAXPositionAttribute
	•	kAXSizeAttribute

Persist Display Mapping
	•	Use NSScreen.deviceDescription["NSScreenNumber"]
	•	Resolve to display UUID, not resolution

⸻

Phase 3 — Restore Engine (Critical Path)

Restore Algorithm (deterministic)

For each saved window:
	1.	Ensure app is running
	•	If not → launch
	2.	Wait for window
	•	Poll AX every 250ms (timeout ~10s)
	3.	Match window
	•	Primary: bundle ID
	•	Secondary: title contains saved title
	4.	Move & resize
	•	Set position
	•	Set size
	5.	Verify
	•	Read back frame
	•	Retry once if mismatched

App Launch

NSWorkspace.shared.launchApplication(
  withBundleIdentifier: bundleId,
  options: [.withoutActivation],
  additionalEventParamDescriptor: nil,
  launchIdentifier: nil
)


⸻

Phase 4 — Menu Bar UI

Menu Structure

● AppName
 ├ Restore
 │   ├ Work
 │   ├ Home
 ├ Save Current Layout…
 ├ —
 ├ Start at Login ✓
 ├ —
 ├ Quit

Implementation
	•	NSStatusBar.system.statusItem
	•	No main window
	•	Modal name prompt on save

⸻

Phase 5 — Auto-Start After Boot ✅

Correct Modern Approach (macOS 13+)

Use Service Management API (no deprecated Login Items).

Steps
	1.	Create helper app target (background, no UI)
	2.	Mark helper as:
	•	LSUIElement = YES
	3.	Register at login:

import ServiceManagement

SMAppService.mainApp.register()

Toggle Support
	•	“Start at Login” menu item
	•	Call:

SMAppService.mainApp.unregister()

Why this is the right way
	•	No user-visible login item clutter
	•	No private APIs
	•	Survives OS updates
	•	Matches Apple-blessed pattern

⸻

Phase 6 — Reliability Hardening

Window Matching Heuristics
	•	Prefer:
	1.	Bundle ID
	2.	Window role
	3.	Title substring
	•	Ignore transient windows (dialogs, popovers)

Timing Safeguards
	•	Exponential backoff when waiting for windows
	•	Graceful skip if a window never appears

⸻

Phase 7 — Packaging & Distribution

Code Signing
	•	Required for AX permissions
	•	Hardened runtime enabled
	•	Accessibility prompt auto-triggers on first use

Distribution Options
	•	Unsigned local tool (for you)
	•	Signed .app
	•	Optional Homebrew Cask later

⸻

Phase 8 — Non-Goals (Explicitly Excluded)

❌ Spaces / Mission Control
❌ Tiling logic
❌ Per-app rules
❌ Cloud sync
❌ Cross-machine layouts

These can be added later but not in v1.
