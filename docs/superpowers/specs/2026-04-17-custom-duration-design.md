# Custom Duration Feature — Design Specification

## Overview

Replace the fixed "5 分钟" duration option with a custom duration input that allows users to specify any duration in minutes or hours, with a history of recently used custom values.

## UI Layout

The custom duration input replaces "5 分钟" in the menu. Layout from top to bottom:

```
[ Number Input ] [ Unit Picker ] [ 开始 ]
─────────────────────────────────────────
最近：{duration1} · {duration2} · {duration3}
─────────────────────────────────────────
  1 小时
  2 小时
  一直保持
─────────────────────────────────────────
  退出
```

## Components

### Custom Duration Input Row

- **Number Input**: `TextField` accepting only numeric input (integers). Placeholder: "30"
- **Unit Picker**: `Picker` with two options — "分钟" (default) and "小时"
- **Start Button**: Triggers activation with the specified duration

**Validation:**
- Minimum: 1 minute (1)
- Maximum: 24 hours (86400 seconds)
- Empty or invalid input → disable Start button
- Non-integer input → ignore via input filter

### History Row

- Shows "最近：" followed by up to 3 recent custom durations as clickable text buttons
- Format: "{value} {unit}" (e.g., "15 分钟", "1 小时")
- Separated by " · " (middle dot)
- Clicking a history item activates that duration immediately

## Data Model

### Storage

```swift
@AppStorage("customDurationHistory") private var historyData: Data = Data()
```

History is stored as a JSON-encoded array of `CustomDurationEntry`:

```swift
struct CustomDurationEntry: Codable, Equatable {
    let value: Int      // numeric value (e.g., 30)
    let unit: Unit      // .minutes or .hours

    enum Unit: String, Codable {
        case minutes
        case hours
    }

    var seconds: TimeInterval {
        TimeInterval(value * (unit == .minutes ? 60 : 3600))
    }

    var displayTitle: String {
        "\(value) \(unit == .minutes ? "分钟" : "小时")"
    }
}
```

**Max history entries:** 3 (most recent first)

**Update logic:**
- On "开始" click: encode new duration as `CustomDurationEntry`, prepend to array, deduplicate, trim to 3
- History is shared across all modes (independent of current `selectedMode`)

## Integration with CaffeineManager

- Custom duration activation calls `caffeine.activate(mode: selectedMode, for: seconds)` where `seconds` comes from `CustomDurationEntry.seconds`
- The history row always shows the same 3 values regardless of current mode or active state

## Validation & Edge Cases

- User types non-numeric → filter to empty string
- User enters 0 or negative → disable Start
- User enters > 1440 (minutes) or > 24 (hours) → disable Start
- History click when already active → restarts timer with new duration
- History is empty → hide "最近：" row entirely
- History contains values that exceed max after unit change → cap at max when activating

## Visual Style

- Input row uses the same spacing and alignment as existing menu items
- Number input width: ~50pt
- Unit picker width: ~60pt
- Start button uses standard `.bordered()` style
- History row: `.caption` font size, secondary foreground color, clickable links
