const compatibility = document.querySelector("#compatibility");
const compatibilityText = document.querySelector("#compatibility-text");

const isSecure = window.isSecureContext;
const supportsSerial = "serial" in navigator;

if (supportsSerial && isSecure) {
  compatibility.classList.add("supported");
  compatibilityText.textContent = "浏览器支持刷机，可以开始";
} else {
  compatibility.classList.add("unsupported");
  compatibilityText.textContent = supportsSerial
    ? "请通过 HTTPS 或 localhost 打开"
    : "请使用电脑端 Chrome 或 Edge";
}
