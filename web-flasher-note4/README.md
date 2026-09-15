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

网页使用 `dist/firmware/eink-reminders-note4.bin`，它是从 ESP-IDF 构建结果合并得到的完整
ESP32-S3 镜像，写入偏移为 `0x0`。此固件仅适用于黑白版 NOTE4，不适用于 NOTE4C。
