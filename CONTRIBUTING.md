# Contributing

感谢关注 GoldBar。

## 提交前检查

请在 macOS 15+ 上运行：

```sh
swift run CoreTests --live
swift run UITests
python3 scripts/build.py
python3 scripts/smoke.py
```

## 代码约定

- 保持原生 Swift / AppKit 实现，避免增加运行时依赖。
- 不提交 `.build/`、`dist/`、应用包、DMG、截图或本机配置。
- 不在代码、Issue 或提交中暴露账号、Cookie、Token 等敏感信息。
- 价格解析和提醒规则变更应同时补充对应测试。
- 这是独立的非工行官方项目，请不要加入工行 Logo 或暗示官方授权的内容。
