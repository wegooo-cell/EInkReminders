# 墨水屏提醒事项 v1.0.0

让墨水屏真正成为 Apple 提醒事项在桌面上的一块安静屏幕。

这个版本的核心创新，是**完全联动 Apple 生态**：它不创建另一套彼此割裂的待办数据，
而是以 Mac 为桥梁，直接同步 Apple 提醒事项。你在 iPhone 或 Mac 上做出的更改会显示到
墨水屏；你在 ZECTRIX NOTE4 上完成的事项，也会写回 Mac，并经 iCloud 同步到 iPhone。

## 本次发布包含

- `墨水屏提醒事项.app`：macOS 13 或更高版本，本地 ad-hoc 签名构建。
- `eink-reminders-note4-v1.0.0.bin`：ZECTRIX NOTE4 黑白版完整固件。
- 中文浏览器刷机页面：无需安装开发工具即可通过 Chrome 或 Edge 刷机。
- 中文扫码配网和手机控制页面。

## 使用前须知

- Mac 必须保持开机并运行“墨水屏提醒事项”，它负责访问 Apple 提醒事项和局域网设备。
- 首次启动 Mac App 时，需要授权访问“提醒事项”和本地网络。
- NOTE4 只支持 2.4 GHz Wi-Fi；不要将设备的 HTTP 服务暴露到公网。
- 浏览器刷机会覆盖 NOTE4 现有固件，请确认设备是黑白版而不是 NOTE4C。

完整安装和使用方法见 `docs/user-manual.md`。
