# AwakeCup

macOS 菜单栏应用，防止系统或屏幕进入休眠状态。

## 功能特性

- 菜单栏图标实时显示唤醒状态
- 三种唤醒模式：系统 + 屏幕、仅系统、仅屏幕（防锁屏）
- 定时选项：自定义分钟/小时、1 小时、2 小时或一直保持
- 支持开机自启动（macOS 13+ 使用系统登录项，早期版本使用 LaunchAgent）
- 支持自动隐藏顶部菜单栏，鼠标移到屏幕顶端时临时显示
- 菜单栏图标支持合并状态徽标：
  - 仅系统：单竖条徽标
  - 仅屏幕：小圆点徽标
  - 系统 + 屏幕：双横条徽标
- 定时模式会在图标外围显示倒计时弧线
- 悬停菜单栏图标可查看当前状态和停止时间

## 系统要求

- macOS 13.0 (Ventura) 或更高版本

## 构建

```bash
# 开发构建
swift build

# 运行
swift run

# 发布构建（生成 DMG）
./Scripts/release_macos.sh
```

发布产物位于 `dist/` 目录。

## 技术实现

- 使用 IOKit 电源管理断言 (`IOPMAssertionCreateWithName`) 控制系统休眠
- 使用 `ServiceManagement.SMAppService` 注册登录项
- SwiftUI `MenuBarExtra` 实现菜单栏界面
- `LSUIElement = true` 隐藏 Dock 图标
