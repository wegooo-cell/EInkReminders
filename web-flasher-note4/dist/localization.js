const exactTranslations = new Map([
  ["Connecting", "正在连接"],
  ["Error", "发生错误"],
  ["Close", "关闭"],
  ["Cancel", "取消"],
  ["Try Again", "重试"],
  ["Back", "返回"],
  ["Next", "下一步"],
  ["Continue", "继续"],
  ["Skip", "跳过"],
  ["Install", "开始刷入"],
  ["Installing", "正在刷入固件"],
  ["Preparing installation", "正在准备安装"],
  ["Preparing installation...", "正在准备安装…"],
  ["Installation prepared", "安装准备完成"],
  ["Installation complete!", "固件刷入完成！"],
  ["Installation failed", "固件刷入失败"],
  ["Erasing", "正在清除设备"],
  ["Erasing device...", "正在清除设备…"],
  ["Device erased", "设备已清除"],
  ["Wrapping up", "正在完成最后步骤"],
  ["All done!", "全部完成！"],
  ["Confirm Installation", "确认安装"],
  ["Erase device", "清除设备"],
  ["Erase User Data", "清除用户数据"],
  ["Logs & Console", "日志与串口控制台"],
  ["Logs", "日志"],
  ["Reset Device", "重启设备"],
  ["Download Logs", "下载日志"],
  ["Visit Device", "打开设备页面"],
  ["Add to Home Assistant", "添加到 Home Assistant"],
  ["Fund Development", "支持项目开发"],
  ["Configure Wi-Fi", "配置 Wi-Fi"],
  ["Trying to connect", "正在尝试连接"],
  ["Scanning for networks", "正在扫描 Wi-Fi"],
  ["Unable to connect", "无法连接"],
  ["Timeout", "连接超时"],
  ["Network", "Wi-Fi 网络"],
  ["Network Name", "Wi-Fi 名称"],
  ["Password", "Wi-Fi 密码"],
  ["Connect", "连接"],
  ["Connect to Wi-Fi", "连接 Wi-Fi"],
  ["Change Wi-Fi", "更换 Wi-Fi"],
  ["Join other…", "加入其他网络…"],
  ["Device connected to the network!", "设备已连接到 Wi-Fi！"],
  ["No port selected", "未选择串口"],
  ["Windows & Mac", "Windows 与 Mac"],
  ["Windows", "Windows"],
  ["Mac", "Mac"],
]);

const patternTranslations = [
  [/^Connected to (.+)$/u, "已连接到 $1"],
  [/^Install (.+)$/u, "安装 $1"],
  [/^Update (.+)$/u, "更新 $1"],
  [/^Writing progress: (\d+)%$/u, "写入进度：$1%"],
  [/^Initialized\. Found (.+)$/u, "初始化完成，检测到 $1"],
  [/^Your (.+) board is not supported\.$/u, "暂不支持 $1 开发板。"],
  [/^Unknown error \((.+)\)$/u, "未知错误（$1）"],
  [/^Downloading firmware (.+) failed: (.+)$/u, "下载固件 $1 失败：$2"],
];

const paragraphTranslations = new Map([
  [
    "If you didn't select a port because you didn't see your device listed, try the following steps:",
    "如果列表里没有你的设备，请按下面步骤检查：",
  ],
  [
    "Make sure that the device is connected to this computer (the one that runs the browser that shows this website)",
    "确认设备已连接到当前打开此网页的电脑。",
  ],
  [
    "Most devices have a tiny light when it is powered on. If yours has one, make sure it is on.",
    "确认设备已经通电；如果板上有电源指示灯，它应该亮起。",
  ],
  [
    "Make sure that the USB cable you use can be used for data and is not a power-only cable.",
    "确认 USB 线支持数据传输，不是只能充电的线。",
  ],
  [
    "Make sure you have the right drivers installed. Below are the drivers for common chips used in ESP devices:",
    "确认电脑已安装正确的 USB 串口驱动。以下是 ESP 设备常见芯片的驱动：",
  ],
  ["(download via blue button with icon)", "（点击带下载图标的蓝色按钮）"],
  ["Connect your device to the network to start using it.", "选择 Wi-Fi 并输入密码，让设备接入网络。"],
  [
    "Do you want to reset your device and erase all user data from your device?",
    "确定要重置设备并清除其中的全部用户数据吗？",
  ],
  [
    "All data on the device will be erased.",
    "设备中的全部数据都会被清除。",
  ],
  [
    "Serial port is not readable/writable. Close any other application using it and try again.",
    "无法读写串口。请关闭正在占用该串口的其他应用，然后重试。",
  ],
  [
    "Serial port is not ready. Close any other application using it and try again.",
    "串口尚未就绪。请关闭正在占用该串口的其他应用，然后重试。",
  ],
  ["Failed to download manifest", "下载固件清单失败，请检查网络后重试。"],
  ["Disconnected", "设备连接已断开。"],
  [
    "Failed to initialize. Try resetting your device or holding the BOOT button while clicking INSTALL.",
    "初始化失败。请重启设备，或按住 OK 键的同时点击“开始刷入”。",
  ],
]);

function translateValue(value) {
  const normalized = value.replace(/\s+/gu, " ").trim();
  if (!normalized) return value;

  let translated = exactTranslations.get(normalized) ?? paragraphTranslations.get(normalized);
  if (!translated) {
    for (const [pattern, replacement] of patternTranslations) {
      if (pattern.test(normalized)) {
        translated = normalized.replace(pattern, replacement);
        break;
      }
    }
  }
  if (!translated) return value;

  const leading = value.match(/^\s*/u)?.[0] ?? "";
  const trailing = value.match(/\s*$/u)?.[0] ?? "";
  return `${leading}${translated}${trailing}`;
}

function translateRoot(root) {
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
  const textNodes = [];
  while (walker.nextNode()) textNodes.push(walker.currentNode);
  for (const node of textNodes) node.nodeValue = translateValue(node.nodeValue ?? "");

  const elements = root.querySelectorAll?.("*") ?? [];
  for (const element of elements) {
    for (const attribute of ["label", "aria-label", "placeholder", "title"]) {
      if (element.hasAttribute(attribute)) {
        element.setAttribute(attribute, translateValue(element.getAttribute(attribute) ?? ""));
      }
    }
    if (element.shadowRoot) translateRoot(element.shadowRoot);
  }
}

document.documentElement.lang = "zh-CN";

// ESP Web Tools uses nested open Shadow DOM and re-renders as flashing advances.
// Revisit it briefly so each newly created step is translated before it is read.
setInterval(() => translateRoot(document), 120);
