# 浏览器刷机页

电脑端 Chrome 或 Edge 可通过 Web Serial 直接安装 ESP32 固件。刷机页必须运行在 HTTPS 或
`localhost` 安全上下文中。

## 本地打开

```bash
cd web-flasher
python3 -m http.server 4173 --directory dist
```

随后访问 `http://localhost:4173`。

## 固件更新后重新打包

```bash
cd web-flasher
./prepare-firmware.sh
```

脚本会先运行 PlatformIO 编译，再按照 ESP32 Dev Module 的 4 MB、DIO、40 MHz 参数生成网页刷机需要的合并固件。
