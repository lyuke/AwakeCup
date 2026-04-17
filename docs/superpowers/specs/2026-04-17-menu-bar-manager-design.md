# Menu Bar Manager Feature — Design Specification

## Overview

Extend AwakeCup from a single-purpose menu bar utility into a menu bar manager that can collect third-party menu bar icons, let the user decide which items remain visible, and provide two ways to access hidden items:

- a hidden-items panel opened from AwakeCup's own menu bar icon
- a temporary expanded strip that visually re-exposes hidden items in the menu bar area

The feature targets macOS menu bar extras owned by other applications. Because AppKit only exposes public APIs for an app's own `NSStatusItem` lifecycle, third-party item management must be built around Accessibility (`AXUIElement`) observation and interaction instead of direct status-item ownership.

## Goals

- Discover menu bar items from other running apps that are accessible through the macOS Accessibility API.
- Let the user classify items into two groups: `Always Visible` and `Hidden`.
- Keep AwakeCup as the control point for hidden items.
- Support both access flows:
  - open hidden items inside a dedicated panel
  - temporarily expose hidden items in a strip aligned with the menu bar
- Persist item grouping, order, and default reveal behavior across launches.
- Degrade safely when permissions are missing or specific items cannot be managed reliably.

## Non-Goals

- Re-register or truly re-parent another app's `NSStatusItem` into AwakeCup.
- Use private APIs, code injection, SIP workarounds, or unsupported menu bar hooks.
- Implement advanced triggers in v1 such as hover reveal, scroll reveal, hotkeys, profiles, or search.
- Build a drag-and-drop layout editor in the first iteration.
- Guarantee management of every menu bar extra on the system. Some items may lack sufficient AX metadata and must remain unmanaged.

## Constraints

### Public API Boundary

Apple's public `NSStatusBar` / `NSStatusItem` APIs allow an app to create and remove its own status items only. There is no public AppKit API for hiding or moving another app's status item. The design therefore treats third-party item management as an Accessibility-driven observation and interaction problem.

### Accessibility Requirement

The feature requires the app to be a trusted Accessibility client via `AXIsProcessTrustedWithOptions`. Without that permission, AwakeCup must not enter a partial management state. Instead, it should show a permission onboarding flow and keep third-party item management disabled.

### Reliability Boundary

Third-party menu bar items vary in AX quality. Some expose stable labels and actions; some do not. The system must classify unsupported or unstable items as `unmanaged` rather than forcing them into hidden behavior.

## Runtime Model

AwakeCup remains a menu bar-first app and continues to launch as an accessory application. The app gains a separate settings window, but does not become a Dock-first product.

Primary entry points:

- `MenuBarExtra`: quick actions, reveal actions, permission state, and shortcut to settings
- `Settings window`: primary management surface for item visibility and ordering

The app only activates to the foreground when opening settings or permission guidance.

## Architecture

The current single-file structure in `Sources/AwakeCup/AwakeCup.swift` should be split so the new feature does not compound all behavior into one root file.

### Module Boundaries

#### `AccessibilityPermissionController`

Responsibilities:

- Check whether AwakeCup is trusted for Accessibility access.
- Request the system prompt through `AXIsProcessTrustedWithOptions`.
- Publish permission state to SwiftUI.
- Expose guidance UI state for onboarding and recovery.

#### `MenuBarInventoryService`

Responsibilities:

- Enumerate accessible menu bar items from the system menu bar.
- Normalize raw AX elements into app-level records.
- Track ownership metadata such as bundle ID, process ID, name, available actions, and geometry.
- Refresh inventory on demand and in response to AX notifications where available.

#### `MenuBarLayoutStore`

Responsibilities:

- Persist item grouping (`alwaysVisible`, `hidden`, `unmanaged`).
- Persist user ordering.
- Persist menu-bar-manager preferences such as default reveal mode and auto-collapse timing.
- Reconcile saved layout against newly scanned inventory.

#### `MenuBarOverlayController`

Responsibilities:

- Control the visual hidden area / temporary expanded strip in the menu bar region.
- Show and hide the expanded strip on demand.
- Auto-collapse the strip after a timeout or loss of interaction.
- Keep geometry aligned with the current screen and menu bar metrics.

#### `HiddenItemsPanelController`

Responsibilities:

- Present the hidden-items panel from AwakeCup's menu bar icon.
- Render hidden items in a compact, clickable list/grid.
- Forward user interaction from panel items to the original AX item.

## Core Interaction Model

### Menu Bar Layout

The conceptual layout for v1 is:

`Always Visible Items | AwakeCup Control Item | Hidden Section / Temporary Expansion Area`

The important behavior is not literal ownership of every icon slot, but controlled visibility and redisclosure from AwakeCup.

### Hidden Items Panel

When the user clicks AwakeCup's control item, AwakeCup can open a panel containing hidden items. Each entry should expose:

- icon or best-effort visual marker
- readable item/app name
- click action forwarded to the original item

This panel is the stable fallback interaction because it does not depend on menu bar re-layout timing.

### Temporary Expanded Strip

When the user chooses `Show Hidden Items`, AwakeCup displays a temporary strip aligned with the menu bar area. Hidden items appear in their stored order and behave like temporarily exposed menu bar content. The strip auto-collapses after a timeout or when the user dismisses it.

This mode should feel like re-expanding hidden menu bar items, but the implementation remains an AwakeCup-managed reveal layer rather than a true transfer of third-party status-item ownership.

### Settings Window

The settings window is the primary management interface. v1 should include a `Menu Bar Layout` section with two visible groups:

- `Always Visible`
- `Hidden`

Each row should show:

- item icon or fallback glyph
- item name
- owning application
- current manageability state

The menu bar menu should not mirror this full management UI. It should only expose quick actions:

- show hidden items
- open hidden-items panel
- open settings
- temporarily pause management

## Data Model

### `MenuBarItemRecord`

The core normalized model should include at least:

- `id`: app-level stable identifier
- `bundleIdentifier`
- `processID`
- `displayName`
- `axRole`
- `axSubrole`
- `frame`
- `actions`
- `manageability`
- `preferredSection`
- `sortIndex`

### Stable Identifier Strategy

Item identity cannot rely on title alone because many menu bar extras expose empty or changing labels. v1 should derive a best-effort stable identifier from a combination of:

- owning app bundle identifier
- AX role / subrole
- action signature
- geometric hints
- additional AX attributes when available

If an item cannot be matched reliably across rescans, it should be treated as a new candidate and not silently overwrite a stored mapping.

### Persistence

The layout store should persist:

- per-item section assignment
- per-item order
- preferred default reveal mode
- auto-collapse duration
- whether the manager is currently enabled

JSON-backed storage is sufficient for v1. The schema should tolerate unknown or missing items during startup reconciliation.

## Item State Model

Each discovered item should end up in one of these states:

- `alwaysVisible`: user wants the item available in the normal visible area
- `hidden`: item is managed by AwakeCup and available through panel / expanded strip
- `unmanaged`: item cannot be safely managed due to missing AX support or unstable identification

`unmanaged` items must remain visible in the system menu bar and be labeled clearly in settings with the reason they are excluded from management.

## Permission and Onboarding Flow

On first launch of the feature:

1. AwakeCup checks AX trust state.
2. If untrusted, AwakeCup requests the system prompt.
3. Until trust is granted, the menu bar manager surface stays disabled.
4. The menu bar menu and settings window show a focused permission explanation with a direct path to System Settings.

If permission is later revoked, the app must:

- stop AX-driven inventory updates
- stop reveal interactions
- preserve stored layout data
- switch the UI back to permission guidance

## Error Handling and Degradation

### Unsupported Items

If an item lacks usable AX attributes or actions, AwakeCup should mark it as `unmanaged` and leave it alone.

### Inventory Drift

If app relaunches, system updates, or menu bar changes cause a saved item to no longer match confidently, AwakeCup should:

- keep the saved record for later reconciliation if appropriate
- avoid forcing the new unmatched item into `hidden`
- surface the mismatch in settings

### Geometry Drift

Full-screen mode, notched displays, auto-hidden menu bars, and multi-display setups may affect overlay placement. v1 should prefer conservative behavior:

- if the expanded strip cannot be positioned confidently, fall back to the hidden-items panel
- do not show a broken or partially off-screen expanded strip

### Interaction Failures

If action forwarding to an AX item fails, AwakeCup should:

- dismiss transient UI if needed
- show a lightweight failure state
- keep the underlying item classification unchanged

## Testing Strategy

### Unit Tests

Add tests for:

- item record normalization from raw scan inputs
- stable identifier generation rules
- layout reconciliation between saved state and refreshed inventory
- unsupported-item classification
- auto-collapse timing state transitions

### Integration / Manual Validation

Validate on real systems for:

- permission onboarding and revocation recovery
- panel-based access to hidden items
- temporary expanded strip show/hide behavior
- persistence after app restart
- mixed environments where some items are manageable and others are not

### Regression Protection

Existing AwakeCup behavior must continue to work:

- caffeine activation / deactivation
- launch at login
- existing menu bar icon state

The menu bar manager must not regress the current sleep-prevention flow.

## V1 Scope

Included in v1:

- Accessibility permission onboarding
- menu bar inventory scan
- `Always Visible` and `Hidden` item grouping
- hidden-items panel
- temporary expanded strip
- item ordering persistence
- clear unsupported-item fallback

Deferred beyond v1:

- drag-and-drop reordering
- hover / scroll / hotkey triggers
- profiles
- search
- advanced menu bar appearance customization
- fully polished multi-display and notch-specific layout behavior

## Implementation Notes For This Repository

- `Sources/AwakeCup/AwakeCup.swift` currently contains the full app. This feature should begin the move toward focused files instead of extending the monolith indefinitely.
- The app already uses `MenuBarExtra` and an `AppDelegate`; the new design should preserve those foundations while adding a settings scene/window and management services.
- The menu bar manager should remain orthogonal to `CaffeineManager`; sleep-prevention behavior is a separate responsibility and should not be coupled to AX scanning logic.
