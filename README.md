# 积存金 GoldBar

一个运行在 macOS 15+ 菜单栏中的工行积存金行情查看工具。

它从工行公开行情页面读取「主动积存」价格，在菜单栏右侧直接显示两位小数，例如 `862.86`；点击价格后可以设置刷新间隔、价格提醒或退出应用。

> **免责声明**：本项目是独立的非工行官方工具，仅供个人学习和行情参考。它不登录工行、不访问账户、不进行交易。价格和解析结果可能因工行网页调整而失效，实际交易请以工行官方渠道为准。

## 功能

- 原生 Swift 6 + AppKit 菜单栏应用
- macOS 15.0 及以上，Apple Silicon / Intel 通用二进制
- 10 / 15 / 20 / 30 / 60 秒刷新间隔
- 价格低于或高于指定阈值时发送 macOS 系统通知
- 上下限提醒可单独启用，也可以同时启用
- 严格低于 / 高于才触发，相等不触发；持续超限只提醒一次
- 网络失败时保留最近一次成功价格并显示 `!`；从未成功时显示 `--.--`
- 无第三方运行时依赖，不需要银行账号或登录

## 数据来源

公开行情页面：

<https://mybank.icbc.com.cn/icbc/newperbank/perbank3/gold/goldaccrual_query_out.jsp>

工行页面本身以约 60 秒更新一次，因此更短的本地刷新间隔不代表行情一定更快更新。

## 下载和安装

在 [Releases](../../releases) 下载 DMG，打开后将「积存金.app」拖入 `Applications`。

首次打开时，macOS 可能因为应用使用本地 ad-hoc 签名而阻止启动：右键应用选择「打开」，或到「系统设置 → 隐私与安全性」选择「仍要打开」。本项目没有 Apple Developer ID 签名或公证，不需要关闭 Gatekeeper。

## 从源码构建

要求：

- macOS 15+
- Xcode Command Line Tools，包含 Swift 6
- Python 3
- Pillow（仅构建图标时使用）

```sh
# 获取源码
git clone https://github.com/Jaunc3y/goldbar-macos.git
cd GoldBar

# 安装构建脚本所需的 Pillow（可使用项目自己的虚拟环境）
python3 -m pip install Pillow

# 核心逻辑和 UI 断言测试
swift run CoreTests --live
swift run UITests

# 构建 arm64 + x86_64 通用 .app 和 DMG
python3 scripts/build.py

# 真实启动、联网取价和连续刷新回归
python3 scripts/smoke.py
```

构建产物位于 `dist/`：

- `dist/积存金.app`
- `dist/GoldBar-1.0.0-universal.dmg`

## 项目结构

```text
Sources/
  GoldCore/       报价模型、网页解析、设置、提醒规则
  GoldUI/         菜单栏、设置窗口和通知
  GoldBar/        应用入口
Tests/
  CoreTests/      核心逻辑断言测试
  UITests/        UI/通知相关断言测试
scripts/
  build.py        双架构编译、紧凑 ICNS、签名和 DMG 打包
  smoke.py        真实应用启动与联网回归
assets/           应用图标源文件
```

## 隐私和权限

- 不收集、不上传用户数据
- 不需要辅助功能、屏幕录制或通讯录权限
- 网络请求只访问上方公开行情地址
- 价格提醒使用 macOS UserNotifications；首次启用时需要用户授权
- 偏好设置保存在本机应用偏好中

## 许可证

本项目采用 MIT License，见 [LICENSE](LICENSE)。

工行名称、页面和数据属于其各自权利人；本项目不代表中国工商银行，也不使用其商标作为应用品牌授权依据。
