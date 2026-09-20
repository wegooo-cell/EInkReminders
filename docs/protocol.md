# 局域网协议 v2

Mac 主动访问 ZECTRIX NOTE4，避免 macOS 防火墙入站配置。所有路径位于设备的 80 端口。

## 写接口要求

所有 `POST` 接口（包括设备自带网页使用的 `/wifi` 与 `/api/device/action`）必须同时满足：

- 带请求头 `X-EInk-Reminders: 1`；
- 使用 IPv4 地址访问设备，`Host` 为 `192.168.1.42` 或 `192.168.1.42:80` 这类形式。

不满足时返回 `403 {"error":"forbidden"}`。自定义请求头让其他网站发起的跨站请求必须先预检，
设备不响应预检，浏览器就不会发出请求；`Host` 限定为 IP 地址，用于挡住 DNS 重绑定。

## `GET /api/status`

返回设备状态：

```json
{
  "deviceId": "a1b2c3d4e5f6",
  "firmwareVersion": "1.0.1-note4",
  "revision": 1789000000000,
  "operationCount": 1,
  "selectedIndex": 2,
  "pageCount": 8,
  "localCompletionPending": true,
  "syncRequested": true,
  "syncRequestId": 7,
  "displayRequested": false,
  "view": "today",
  "syncRequestAgeMs": 1200,
  "width": 400,
  "height": 300,
  "pixelFormat": "1bpp-msb-1white"
}
```

- `view`：设备当前视图，`today`、`scheduled`、`all` 或 `completed`。Mac 只读取该视图的 EventKit 数据。
- `syncRequested` / `syncRequestId`：设备请求 Mac 同步，每次请求分配新的序号。设备启动、Wi-Fi 恢复、
  本地完成或延后、切换视图、手动同步、清除画面缓存时都会发起请求。
- `syncRequestAgeMs`：距离请求的毫秒数。本地完成会把请求推迟 5 秒，Mac 在请求满 5 秒后再同步，
  连续完成的多项一起写回。
- `displayRequested` / `selectedIndex`：按键需要的画面尚未缓存，Mac 按该序号生成画面。

## `POST /api/snapshot`

`Content-Type: application/json`，请求体上限 512 KB。发送当前视图的事项和到点提醒：

```json
{
  "revision": 1789000000000,
  "view": "today",
  "reminders": [
    {
      "syncId": "8f0c…",
      "appleId": "x-apple-reminder://…",
      "completed": false
    }
  ],
  "currentViewCount": 12,
  "replaceDisplay": true,
  "sentAtEpochMs": 1789000000000,
  "alerts": [
    {
      "syncId": "8f0c…",
      "appleId": "x-apple-reminder://…",
      "dueAtEpochMs": 1789000300000,
      "bitmap": "<base64>"
    }
  ]
}
```

- `view` 必须等于设备当前视图，否则返回 `409 {"error":"view_mismatch"}`。同步期间在设备上切换了视图时，
  旧视图的快照不会被当作新视图显示。
- `reminders` 只带 `syncId`、`appleId`、`completed`，标题、备注等内容不以明文上传。设备按视图保留事项：
  「完成」视图只保留已完成事项，其他视图只保留未完成事项，顺序即按键选择顺序。
- `sentAtEpochMs` 用于校准设备时钟，到点提醒依赖它判断时间。
- `alerts` 最多 32 项，`bitmap` 为 280 × 78、1 bpp、MSB 在前的提醒卡片文字图。
- `replaceDisplay=true` 表示本轮会重新上传画面：设备清除已缓存的画面，并把选中位置重置到第一项。
  为 `false` 时保留当前选中状态与已缓存画面。

成功返回 `204`。

## `POST /api/display?index=<n>&state=<normal|idle|confirm>`

`Content-Type: application/octet-stream`，请求体必须恰好为 15,000 字节
（400 × 300 ÷ 8）。每行 50 字节，MSB 为左侧像素，`1` 表示白，`0` 表示黑。

| `state` | 含义 |
| --- | --- |
| `idle` | 没有选中背景的列表画面；平时显示它，按键空闲 30 秒后也回到它 |
| `normal` | 选中第 `index` 项的画面 |
| `confirm` | 在第 `index` 项按 OK 后的预测画面，设备按下 OK 时立即显示 |

设备每种状态只缓存一幅画面。成功返回 `202 {"accepted":true}`，存储失败返回 `507`。

## `GET /api/operations?after=<sequence>`

返回 sequence 大于参数的操作：

```json
{
  "operations": [
    {
      "sequence": 13,
      "type": "setCompleted",
      "syncId": "8f0c…",
      "appleId": "x-apple-reminder://…",
      "completed": true
    },
    {
      "sequence": 14,
      "type": "setDueAt",
      "syncId": "8f0c…",
      "completed": false,
      "dueAtEpochMs": 1789000300000
    }
  ]
}
```

- `setCompleted`：在列表中按 OK，或在到点提醒中选择「完成」。
- `setDueAt`：在到点提醒中选择「5 分钟」，`dueAtEpochMs` 为新的到期时间（对齐到整分钟）。

操作保存在设备 Flash 中，断电不丢失，直到被确认。

## `POST /api/operations/ack`

```json
{"through": 13}
```

设备只删除 sequence 小于等于 `through` 的操作，成功返回 `204`。

## `POST /api/sync/ack`

```json
{"requestId": 7}
```

`requestId` 为本轮同步开始时从 `/api/status` 读到的 `syncRequestId`。只有它等于设备当前请求序号时才清除
同步请求；同步期间设备产生的新请求序号更大，会被保留，Mac 随后再同步一次。成功返回 `204`。

## 同步顺序

1. Mac 读取 `/api/status`，校验屏幕为 400 × 300。
2. 读取全部未确认操作，写回 Apple 提醒事项。
3. 读取当前视图的事项，发送快照；需要时上传 `idle`、`normal` 与 `confirm` 画面。
4. 上述步骤全部成功后，确认操作与同步请求。

完成状态双向传播：设备上的完成通过操作写回 Apple 提醒事项，在 Mac 或 iPhone 上完成的事项在下一次快照中移除。
设备只提交完成与延后两类操作，不会新增或删除 Apple 提醒事项。
