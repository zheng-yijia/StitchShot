"use strict";

// 上报页面尺寸；响应逐屏滚动指令（等待页面稳定后返回实际滚动位置）。
browser.runtime.onMessage.addListener((message, sender) => {
    if (!message) {
        return undefined;
    }

    if (message.type === "page-metrics") {
        const doc = document.documentElement;
        return Promise.resolve({
            width: Math.max(doc.scrollWidth, doc.clientWidth),
            height: Math.max(doc.scrollHeight, doc.clientHeight),
            viewportWidth: window.innerWidth,
            viewportHeight: window.innerHeight,
            devicePixelRatio: window.devicePixelRatio || 1
        });
    }

    if (message.type === "scroll-to") {
        const settle = typeof message.settle === "number" ? message.settle : 200;
        window.scrollTo(0, message.y);
        return new Promise((resolve) => {
            setTimeout(() => {
                const doc = document.documentElement;
                resolve({
                    scrollY: window.scrollY,
                    reachedBottom: window.scrollY + window.innerHeight >= doc.scrollHeight - 1
                });
            }, settle);
        });
    }

    return undefined;
});
