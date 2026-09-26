"use strict";

// 整页捕获：content.js 逐屏滚动，本脚本逐屏 captureVisibleTab，
// 每帧经 sendNativeMessage 交给原生端写入 App Group，
// 结束后主 App 用拼接引擎合成为整页长图。

const MAX_FRAMES = 60;
const SCROLL_SETTLE_MS = 260;

function sendNative(payload) {
    return browser.runtime.sendNativeMessage(payload);
}

function reportProgress(index, total) {
    browser.runtime.sendMessage({
        type: "capture-progress",
        index: index,
        total: total
    }).catch(() => {});
}

async function captureFullPage() {
    const tabs = await browser.tabs.query({ active: true, currentWindow: true });
    const tab = tabs[0];
    if (!tab) {
        return { ok: false, reason: "no-tab" };
    }

    let metrics;
    try {
        metrics = await browser.tabs.sendMessage(tab.id, { type: "page-metrics" });
    } catch (error) {
        return { ok: false, reason: "no-content-script" };
    }

    const sessionID = "web-" + Date.now() + "-" + Math.floor(Math.random() * 100000);
    const begin = await sendNative({ type: "begin", sessionID: sessionID });
    if (!begin || !begin.ok) {
        return { ok: false, reason: "native-begin-failed" };
    }

    const step = Math.max(1, metrics.viewportHeight);
    const totalHeight = Math.max(metrics.height, step);
    const estimatedTotal = Math.min(MAX_FRAMES, Math.ceil(totalHeight / step));

    let y = 0;
    let index = 0;
    try {
        while (index < MAX_FRAMES) {
            const scroll = await browser.tabs.sendMessage(tab.id, {
                type: "scroll-to",
                y: y,
                settle: SCROLL_SETTLE_MS
            });
            const dataUrl = await browser.tabs.captureVisibleTab(tab.windowId, { format: "png" });
            const frame = await sendNative({
                type: "frame",
                sessionID: sessionID,
                index: index,
                imageData: dataUrl.split(",")[1]
            });
            if (!frame || !frame.ok) {
                throw new Error("native-frame-failed");
            }
            index += 1;
            reportProgress(index, estimatedTotal);

            const currentY = typeof scroll.scrollY === "number" ? scroll.scrollY : y;
            if (scroll.reachedBottom || currentY + step >= totalHeight - 1) {
                break;
            }
            y = currentY + step;
        }
    } catch (error) {
        return { ok: false, reason: "capture-aborted" };
    } finally {
        browser.tabs.sendMessage(tab.id, { type: "scroll-to", y: 0, settle: 50 }).catch(() => {});
    }

    const end = await sendNative({
        type: "end",
        sessionID: sessionID,
        frameCount: index,
        pageURL: tab.url || ""
    });
    if (!end || !end.ok) {
        return { ok: false, reason: "native-end-failed" };
    }
    return { ok: true, frames: index };
}

browser.runtime.onMessage.addListener((message, sender) => {
    if (!message) {
        return undefined;
    }
    if (message.type === "capture-visible") {
        return browser.tabs.captureVisibleTab(undefined, { format: "png" }).then((dataUrl) => {
            return sendNative({
                type: "capture",
                imageData: dataUrl.split(",")[1]
            });
        });
    }
    if (message.type === "capture-full-page") {
        return captureFullPage();
    }
    return undefined;
});
