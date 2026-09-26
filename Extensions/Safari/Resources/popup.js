"use strict";

const fullButton = document.getElementById("capture-full");
const visibleButton = document.getElementById("capture-visible");
const status = document.getElementById("status");

function setBusy(busy) {
    fullButton.disabled = busy;
    visibleButton.disabled = busy;
}

browser.runtime.onMessage.addListener((message) => {
    if (message && message.type === "capture-progress") {
        status.textContent = "正在截取 " + message.index + " / 约 " + message.total + " 屏…";
    }
    return undefined;
});

fullButton.addEventListener("click", () => {
    setBusy(true);
    status.textContent = "正在截取…";

    browser.runtime.sendMessage({ type: "capture-full-page" }).then((response) => {
        if (response && response.ok) {
            status.textContent = "已完成 " + response.frames + " 屏，打开 StitchShot 拼接";
        } else {
            status.textContent = "截取失败：" + ((response && response.reason) || "未知原因");
        }
        setBusy(false);
    }).catch(() => {
        status.textContent = "截取失败";
        setBusy(false);
    });
});

visibleButton.addEventListener("click", () => {
    setBusy(true);
    status.textContent = "正在截取…";

    browser.runtime.sendMessage({ type: "capture-visible" }).then((response) => {
        status.textContent = response && response.ok ? "已存入 StitchShot 收件箱" : "保存失败";
        setBusy(false);
    }).catch(() => {
        status.textContent = "截取失败";
        setBusy(false);
    });
});
