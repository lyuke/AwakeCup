# Custom Duration Feature — Implementation Plan

> **For agenting workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the "5 分钟" fixed duration option with a custom duration input (number + unit picker) and a history row showing the 3 most recent custom values.

**Architecture:** All changes live in `Sources/AwakeCup/AwakeCup.swift`. `CustomDurationEntry` struct added near the top of the file. `DurationOption` enum remains but its `.fiveMinutes` case is removed. Custom input and history are managed via `@AppStorage` persisted in the `AwakeCupApp` struct.

**Tech Stack:** SwiftUI, @AppStorage, Codable JSON

---

### Task 1: Add `CustomDurationEntry` struct and `DurationUnit` enum

**Files:**
- Modify: `Sources/AwakeCup/AwakeCup.swift:479` (before `DurationOption` enum)

- [ ] **Step 1: Add struct after line 478 (after `MenuBarIcon` closing brace)**

Insert this code right before `private enum DurationOption`:

```swift
struct CustomDurationEntry: Codable, Equatable, Identifiable {
    let value: Int
    let unit: Unit

    enum Unit: String, Codable, CaseIterable, Identifiable {
        case minutes
        case hours

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .minutes: return "分钟"
            case .hours: return "小时"
            }
        }

        var maxValue: Int {
            switch self {
            case .minutes: return 1440  // 24 hours
            case .hours: return 24
            }
        }

        var secondsPerUnit: Int {
            switch self {
            case .minutes: return 60
            case .hours: return 3600
            }
        }
    }

    var id: String { "\(value)-\(unit.rawValue)" }

    var seconds: TimeInterval {
        TimeInterval(value * unit.secondsPerUnit)
    }

    var displayTitle: String {
        "\(value) \(unit.displayName)"
    }

    var isValid: Bool {
        value >= 1 && value <= unit.maxValue
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Sources/AwakeCup/AwakeCup.swift
git commit -m "feat: add CustomDurationEntry struct and DurationUnit enum"
```

---

### Task 2: Remove `.fiveMinutes` from `DurationOption` enum

**Files:**
- Modify: `Sources/AwakeCup/AwakeCup.swift:479` (the `DurationOption` enum)

- [ ] **Step 1: Edit the enum to remove `.fiveMinutes` case and its cases in `title` and `seconds`**

Find the `DurationOption` enum (around line 479) and replace the entire enum with:

```swift
private enum DurationOption: Identifiable, CaseIterable {
    case oneHour
    case twoHours
    case indefinite

    var id: String { title }

    var title: String {
        switch self {
        case .oneHour: return "1 小时"
        case .twoHours: return "2 小时"
        case .indefinite: return "一直保持"
        }
    }

    var seconds: TimeInterval? {
        switch self {
        case .oneHour: return 60 * 60
        case .twoHours: return 2 * 60 * 60
        case .indefinite: return nil
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Sources/AwakeCup/AwakeCup.swift
git commit -m "refactor: remove .fiveMinutes from DurationOption (replaced by custom input)"
```

---

### Task 3: Add state and history management in `AwakeCupApp`

**Files:**
- Modify: `Sources/AwakeCup/AwakeCup.swift:524` (the `AwakeCupApp` struct)

- [ ] **Step 1: Add state variables after the existing `@State` declarations (after line 530)**

Find the `@State private var isApplyingLaunchAtLogin: Bool = false` line and add the following state properties after it:

```swift
    @State private var customDurationValue: String = ""
    @State private var customDurationUnit: CustomDurationEntry.Unit = .minutes
    @AppStorage("customDurationHistory") private var historyData: Data = Data()

    private var history: [CustomDurationEntry] {
        get {
            (try? JSONDecoder().decode([CustomDurationEntry].self, from: historyData)) ?? []
        }
        set {
            historyData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    private var canActivateCustom: Bool {
        guard !customDurationValue.isEmpty,
              let intValue = Int(customDurationValue),
              intValue >= 1,
              intValue <= customDurationUnit.maxValue else { return false }
        return true
    }

    private func activateCustom() {
        guard let intValue = Int(customDurationValue),
              intValue >= 1,
              intValue <= customDurationUnit.maxValue else { return }

        let entry = CustomDurationEntry(value: intValue, unit: customDurationUnit)

        // Update history
        var updated = history.filter { $0 != entry }
        updated.insert(entry, at: 0)
        if updated.count > 3 { updated = Array(updated.prefix(3)) }
        history = updated

        // Activate
        caffeine.activate(mode: selectedMode, for: entry.seconds)
    }

    private func activateFromHistory(_ entry: CustomDurationEntry) {
        // Cap at max if needed
        let cappedValue = min(entry.value, entry.unit.maxValue)
        let safeEntry = CustomDurationEntry(value: cappedValue, unit: entry.unit)
        caffeine.activate(mode: selectedMode, for: safeEntry.seconds)
    }
```

- [ ] **Step 2: Commit**

```bash
git add Sources/AwakeCup/AwakeCup.swift
git commit -m "feat: add custom duration state, history storage, and activation helpers"
```

---

### Task 4: Replace "5 分钟" in menu with custom input UI

**Files:**
- Modify: `Sources/AwakeCup/AwakeCup.swift:595` (the `ForEach(DurationOption.allCases)` loop in the menu body)

- [ ] **Step 1: Replace the `ForEach` block for duration options**

Find the `ForEach(DurationOption.allCases) { option in` block (around line 595) and replace it with the custom input section. The block currently looks like:

```swift
ForEach(DurationOption.allCases) { option in
    Button(option.title) {
        if let seconds = option.seconds {
            caffeine.activate(mode: selectedMode, for: seconds)
        } else {
            caffeine.activateIndefinitely(mode: selectedMode)
        }
    }
    .disabled((caffeine.isSystemActive || caffeine.isDisplayActive) && option == .indefinite && caffeine.activeUntil == nil && caffeine.activeMode == selectedMode)
}
```

Replace it with:

```swift
// Custom duration input
HStack(spacing: 4) {
    TextField("30", text: $customDurationValue)
        .textFieldStyle(.roundedBorder)
        .frame(width: 50)
        .keyboardType(.numberPad)
        .onChange(of: customDurationValue) { newValue in
            // Filter non-numeric characters
            let filtered = newValue.filter { $0.isNumber }
            if filtered != newValue {
                customDurationValue = filtered
            }
        }

    Picker("", selection: $customDurationUnit) {
        ForEach(CustomDurationEntry.Unit.allCases) { unit in
            Text(unit.displayName).tag(unit)
        }
    }
    .labelsHidden()
    .pickerStyle(.menu)
    .frame(width: 60)

    Button("开始") {
        activateCustom()
    }
    .disabled(!canActivateCustom)
    .buttonStyle(.bordered)
}

// History row
if !history.isEmpty {
    HStack(spacing: 2) {
        Text("最近：")
            .font(.caption)
            .foregroundStyle(.secondary)
        ForEach(history) { entry in
            Button(entry.displayTitle) {
                activateFromHistory(entry)
            }
            .font(.caption)
            .buttonStyle(.link)
            if entry.id != history.last?.id {
                Text("·")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

Divider()

// Fixed duration options
ForEach(DurationOption.allCases) { option in
    Button(option.title) {
        if let seconds = option.seconds {
            caffeine.activate(mode: selectedMode, for: seconds)
        } else {
            caffeine.activateIndefinitely(mode: selectedMode)
        }
    }
    .disabled((caffeine.isSystemActive || caffeine.isDisplayActive) && option == .indefinite && caffeine.activeUntil == nil && caffeine.activeMode == selectedMode)
}
```

- [ ] **Step 2: Verify the build compiles**

```bash
swift build 2>&1 | head -30
```

Expected: Build succeeds with no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/AwakeCup/AwakeCup.swift
git commit -m "feat: replace 5 minutes with custom duration input and history row

- Add HStack with number TextField + unit Picker + Start button
- Add history row showing up to 3 recent custom durations
- Filter non-numeric input in TextField
- History persists via @AppStorage as JSON-encoded array

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 5: Final verification

- [ ] **Step 1: Build in release mode**

```bash
swift build -c release 2>&1 | tail -5
```

Expected: Build succeeds.

- [ ] **Step 2: Run the app and verify manually**

```bash
swift run
```

Check:
1. Menu shows custom input row at top of duration section
2. Number input filters non-numeric characters
3. Start button disabled when input is empty or out of range (0, negative, > 1440 min / > 24 hr)
4. After clicking "开始", history row appears with the value
5. Clicking a history item activates that duration
6. History updates correctly (deduped, max 3 entries)
7. Fixed options (1 小时, 2 小时, 一直保持) still work correctly

---

## Spec Coverage Check

| Spec Requirement | Task |
|---|---|
| `CustomDurationEntry` struct with value, unit, seconds, displayTitle | Task 1 |
| `Unit` enum with minutes/hours, displayName, maxValue, secondsPerUnit | Task 1 |
| Remove `.fiveMinutes` from `DurationOption` | Task 2 |
| `@AppStorage` history storage | Task 3 |
| History read/write logic (max 3, dedup, prepend) | Task 3 |
| `canActivateCustom` validation (min 1, max range) | Task 3 |
| Number input with non-numeric filter | Task 4 |
| Unit picker with "分钟"/"小时" options | Task 4 |
| Start button disabled when invalid | Task 4 |
| History row with up to 3 entries, clickable | Task 4 |
| History hidden when empty | Task 4 |
| History click activates duration | Task 4 |
| Integration with `CaffeineManager.activate(mode:for:)` | Task 4 |
