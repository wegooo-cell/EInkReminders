# Contributing / 参与贡献

Thank you for helping improve the ZECTRIX NOTE4 reference demo. Bug reports,
documentation fixes and focused pull requests are welcome.

感谢你参与改进 ZECTRIX NOTE4 参考 Demo。欢迎提交问题报告、文档修正和范围清晰的
Pull Request。

## Before opening an issue / 提交 Issue 前

Please include the following information when reporting a problem:

- the exact device model and hardware revision;
- the ESP-IDF version (`idf.py --version`);
- the build or runtime log with credentials, Wi-Fi names, MAC addresses and
  other personal data removed;
- the smallest sequence of steps that reproduces the problem;
- whether the issue occurs on USB power, battery power or both.

提交问题时，请提供准确的设备型号和硬件版本、ESP-IDF 版本、去除凭据和个人信息后的
日志、最短复现步骤，以及问题发生在 USB 供电、电池供电还是两种情况下。

## Pull requests / 代码贡献

1. Keep each pull request focused on one change.
2. Build from a clean checkout with ESP-IDF 5.4 or later.
3. For display or hardware changes, describe the physical device validation
   performed and attach only non-sensitive evidence.
4. Update the relevant document under `docs/` when behavior or a public API
   changes.
5. Do not commit Wi-Fi credentials, device secrets, raw flash backups, captured
   audio or generated `sdkconfig` and build directories.

请保持每个 Pull Request 只解决一个明确问题；使用 ESP-IDF 5.4 或更高版本从干净
环境构建；涉及屏幕或硬件时说明真机验证情况；行为或公开 API 变化时同步更新
`docs/`；严禁提交 Wi-Fi 凭据、设备密钥、原始 Flash 备份、录音、生成的
`sdkconfig` 或构建目录。

## Validation / 验证

```bash
idf.py set-target esp32s3
idf.py build
idf.py size
```

Do not flash hardware solely to validate a documentation-only change. If a
hardware write is necessary, confirm that the target is the black-and-white
ZECTRIX NOTE4 and use its exact serial port.

仅修改文档时无需为了验证而烧录设备。如确需写入硬件，请先确认目标是黑白墨水屏版
ZECTRIX NOTE4，并使用该设备的准确串口。
