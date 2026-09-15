# 局域网协议 v2

Mac 主动访问 ESP32，避免 macOS 防火墙入站配置。所有路径位于设备的 80 端口。

## `GET /api/status`

返回设备状态：

```json
{"deviceId":"a1b2c3d4","revision":12,"operationCount":1,"width":400,"height":300,"view":"today","selectedIndex":7,"displayRequested":true,"syncRequested":false}
```

## `POST /api/snapshot`

发送当前事项元数据。ESP32 使用第一条未完成事项作为初始 BOOT 选中目标。

```json
{
  "revision": 12,
  "currentViewCount": 20,
  "replaceDisplay": true,
  "reminders": [
    {"syncId":"...","title":"买咖啡豆","completed":false,"dueAt":"2026-09-10T10:00:00+08:00","hasDueTime":true}
  ]
}
```

## `POST /api/display?index=<n>&state=<normal|idle|confirm>`

`Content-Type: application/octet-stream`，请求体必须恰好为 38880 字节
（648 × 480 ÷ 8）。每行 81 字节，MSB 为左侧像素，`1` 表示黑，`0` 表示白。
设备只缓存当前选择画面、无选择画面和确认预览三幅图。按键改变选择后，`displayRequested=true`，Mac 根据 `selectedIndex` 按需生成并发送新画面。`confirm` 画面用于按下 OK 后立即显示完成状态，不再预先上传所有完成组合。

## `GET /api/operations?after=<sequence>`

返回 sequence 大于参数的操作：

```json
{"operations":[{"sequence":13,"type":"setCompleted","syncId":"...","completed":true}]}
```

## `POST /api/operations/ack`

```json
{"through":13}
```

设备只删除 sequence 小于等于 `through` 的操作。

NOTE4 在 `/api/status` 中用 `view` 返回当前视图：`today`、`scheduled`、`all` 或
`completed`。Mac 只读取该视图的 EventKit 数据，并通过 `currentViewCount` 回传当前视图数量。
`replaceDisplay=true` 表示本轮会重新上传画面，设备可先清理旧的本地完成状态缓存。

## 冲突规则

1. 设备操作先应用到 EventKit，再重新拉取完整快照。
2. 相同 `syncId` 的普通字段采用更新时间较新的版本。
3. MVP 不传播删除；完成状态可以双向传播。
4. 新增事项由设备生成 UUID，Mac 保存映射后沿用该 UUID。
