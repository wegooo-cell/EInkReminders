# ZECTRIX NOTE4 墨水屏提醒事项固件

[English](README.md) | 中文

这是 Apple 提醒事项双向同步项目的 ZECTRIX NOTE4 版本，基于 ZECTRIX 官方
`zectrix-note4-epd-demo` 的 MIT 开源屏幕、主板和按键驱动。

## 功能

- 适配 NOTE4 黑白版的 400 × 300 SSD2683 屏幕。
- 上键/下键首尾循环选择上一项/下一项，OK 单击确认完成；可连续确认多个项目。
- 每次确认后立即显示勾选与删除线；连续确认时保留完成状态。最后一次确认 5 秒后由 Mac 自动同步，刷新后移除这些项目。
- 今天、计划和完成视图最多浏览 20 项；全部视图不设应用层项目上限。设备只缓存当前画面并向 Mac 按需请求下一项，减少同步等待和闪存占用。
- 所有画面切换均采用 1bpp 全屏刷新。
- 使用与微雪版本相同的局域网同步 API；Mac 应用自动识别显示格式。
- 未配网或连接失败时建立 `EInk-Note4-XXXX` 热点，在屏幕显示适配 iPhone 的
  Wi-Fi 二维码，并通过系统配网门户提供完整中文流程。
- 最多保存五个选中状态页面；离线完成操作保存在 NVS，断电不丢失。

## 构建

需要 ESP-IDF 5.4 或更高版本：

```bash
idf.py set-target esp32s3
idf.py build
idf.py -p /dev/cu.usbmodemXXXX flash monitor
```

首次启动后用 iPhone 相机扫描屏幕二维码并加入 `EInk-Note4-XXXX`；中文配网页面
通常会自动打开。未自动弹出时访问 `http://192.168.4.1`。从列表选择 2.4 GHz
Wi-Fi，固件会在验证成功后保存配置。完整步骤见项目根目录的 `docs/zectrix-note4.md`。

> 仅适用于黑白 NOTE4，不适用于 NOTE4C。刷机会覆盖原厂固件。

## 开源来源

NOTE4 驱动和硬件适配来自 ZECTRIX Lab 的
[`zectrix-note4-epd-demo`](https://github.com/itopinion/zectrix-note4-epd-demo)，
按 MIT License 使用。原许可证及第三方声明保留在本目录。
