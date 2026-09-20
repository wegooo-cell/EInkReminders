# ZECTRIX NOTE4 浏览器刷机页

电脑端 Chrome 或 Edge 可通过 Web Serial 为黑白版 ZECTRIX NOTE4 安装“墨水屏提醒事项”。
它以 Mac 为桥梁，与 Apple 提醒事项、Mac 和 iPhone 双向联动。
刷机页必须运行在 HTTPS 或 `localhost` 安全上下文中。

公开刷机地址：<https://wegooo-cell.github.io/EInkReminders/>

## 本地预览

```bash
cd web-flasher-note4
python3 -m http.server 4184 --directory dist
```

随后访问 `http://localhost:4184`。

## 固件

`dist/firmware/manifest.json` 把 v1.0.1 固件分三段写入，不覆盖 `0x9000` 起的 NVS 分区：

| 文件 | 写入偏移 |
| --- | --- |
| `bootloader-v1.0.1.bin` | `0x0` |
| `partition-table-v1.0.1.bin` | `0x8000` |
| `eink-reminders-note4-app-v1.0.1.bin` | `0x10000` |

刷机时不勾选“清除设备”，设备会保留：

- 已保存的 Wi-Fi
- 待同步的操作
- 视图选择

三段文件从 Release 附件 `eink-reminders-note4-v1.0.1.bin` 原样切出。

此固件仅适用于黑白版 NOTE4，不适用于 NOTE4C。

## 刷机组件

`dist/vendor/esp-web-tools/10.4.0/` 自托管固定版本的 [ESP Web Tools](https://github.com/esphome/esp-web-tools)：

- 内容：npm 包中的 `dist/web` 构建产物
- 许可证：Apache-2.0，见同目录 `LICENSE`
