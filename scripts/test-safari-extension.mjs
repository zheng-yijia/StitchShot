// Safari 扩展 JS 逻辑验证（Node 模拟 WebExtension API）。
// 运行：node scripts/test-safari-extension.mjs
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import { fileURLToPath } from "node:url";
import path from "node:path";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const safariDir = path.join(root, "Extensions", "Safari", "Resources");

let passed = 0;
function test(name, fn) {
    return Promise.resolve()
        .then(fn)
        .then(() => {
            passed += 1;
            console.log(`ok ${passed} - ${name}`);
        })
        .catch((error) => {
            console.error(`not ok - ${name}`);
            console.error(error);
            process.exitCode = 1;
        });
}

// ---------- 模拟页 ----------

function makePage({ scrollHeight, viewportHeight = 800 }) {
    const state = { scrollY: 0 };
    return {
        viewportHeight,
        metrics: {
            width: 390,
            height: scrollHeight,
            viewportWidth: 390,
            viewportHeight,
            devicePixelRatio: 3
        },
        scrollTo(y) {
            state.scrollY = Math.min(y, Math.max(0, scrollHeight - viewportHeight));
        },
        get scrollY() {
            return state.scrollY;
        },
        get reachedBottom() {
            return state.scrollY + viewportHeight >= scrollHeight - 1;
        }
    };
}

// ---------- browser API mock ----------

function makeBrowser({ page, nativeHandler, failOnContentScript = false }) {
    const nativeCalls = [];
    const progressEvents = [];
    const listeners = [];
    const browser = {
        nativeCalls,
        progressEvents,
        runtime: {
            onMessage: {
                addListener(fn) {
                    listeners.push(fn);
                }
            },
            sendNativeMessage(payload) {
                nativeCalls.push(payload);
                return Promise.resolve(nativeHandler(payload));
            },
            sendMessage(payload) {
                if (payload && payload.type === "capture-progress") {
                    progressEvents.push(payload);
                }
                return Promise.resolve(undefined);
            }
        },
        tabs: {
            query() {
                return Promise.resolve([{ id: 7, windowId: 1, url: "https://example.com/page" }]);
            },
            sendMessage(tabId, message) {
                if (failOnContentScript) {
                    return Promise.reject(new Error("no receiver"));
                }
                if (message.type === "page-metrics") {
                    return Promise.resolve(page.metrics);
                }
                if (message.type === "scroll-to") {
                    page.scrollTo(message.y);
                    return Promise.resolve({
                        scrollY: page.scrollY,
                        reachedBottom: page.reachedBottom
                    });
                }
                return Promise.reject(new Error("unexpected message " + message.type));
            },
            captureVisibleTab() {
                return Promise.resolve("data:image/png;base64,QUJD");
            }
        },
        dispatch(message) {
            return listeners[0](message, {});
        }
    };
    return browser;
}

function loadScript(name, sandbox) {
    const code = readFileSync(path.join(safariDir, name), "utf8");
    vm.runInNewContext(code, sandbox, { filename: name });
}

const defaultNative = (payload) => ({ ok: true });

// ---------- background.js 用例 ----------

await test("三屏页面：begin → 3 帧 → end，滚动序列 0/800/1600", async () => {
    const page = makePage({ scrollHeight: 2400 });
    const browser = makeBrowser({ page, nativeHandler: defaultNative });
    loadScript("background.js", { browser, console });

    const result = await browser.dispatch({ type: "capture-full-page" });
    assert.equal(result.ok, true);
    assert.equal(result.frames, 3);

    const types = browser.nativeCalls.map((c) => c.type);
    assert.deepEqual(types, ["begin", "frame", "frame", "frame", "end"]);

    const frames = browser.nativeCalls.filter((c) => c.type === "frame");
    assert.deepEqual(frames.map((f) => f.index), [0, 1, 2]);
    assert.equal(frames[0].imageData, "QUJD");

    const end = browser.nativeCalls.at(-1);
    assert.equal(end.frameCount, 3);
    assert.equal(end.pageURL, "https://example.com/page");

    assert.deepEqual(
        browser.progressEvents.map((e) => e.index),
        [1, 2, 3]
    );
});

await test("不足一屏的页面：仅截 1 帧", async () => {
    const page = makePage({ scrollHeight: 700 });
    const browser = makeBrowser({ page, nativeHandler: defaultNative });
    loadScript("background.js", { browser, console });

    const result = await browser.dispatch({ type: "capture-full-page" });
    assert.equal(result.ok, true);
    assert.equal(result.frames, 1);
    const types = browser.nativeCalls.map((c) => c.type);
    assert.deepEqual(types, ["begin", "frame", "end"]);
});

await test("两屏半页面：末屏滚动被钳制，仍正确到底（3 帧）", async () => {
    const page = makePage({ scrollHeight: 2000 });
    const browser = makeBrowser({ page, nativeHandler: defaultNative });
    loadScript("background.js", { browser, console });

    const result = await browser.dispatch({ type: "capture-full-page" });
    assert.equal(result.ok, true);
    assert.equal(result.frames, 3);
});

await test("原生端写帧失败：中止且不发 end", async () => {
    const page = makePage({ scrollHeight: 2400 });
    const browser = makeBrowser({
        page,
        nativeHandler: (payload) => ({ ok: payload.type !== "frame" || payload.index === 0 })
    });
    loadScript("background.js", { browser, console });

    const result = await browser.dispatch({ type: "capture-full-page" });
    assert.equal(result.ok, false);
    assert.equal(result.reason, "capture-aborted");
    assert.equal(browser.nativeCalls.some((c) => c.type === "end"), false);
});

await test("页面未注入 content script：返回 no-content-script", async () => {
    const page = makePage({ scrollHeight: 2400 });
    const browser = makeBrowser({ page, nativeHandler: defaultNative, failOnContentScript: true });
    loadScript("background.js", { browser, console });

    const result = await browser.dispatch({ type: "capture-full-page" });
    assert.equal(result.ok, false);
    assert.equal(result.reason, "no-content-script");
});

await test("单屏可见区域捕获：走 capture 通道", async () => {
    const page = makePage({ scrollHeight: 2400 });
    const browser = makeBrowser({ page, nativeHandler: defaultNative });
    loadScript("background.js", { browser, console });

    const result = await browser.dispatch({ type: "capture-visible" });
    assert.equal(result.ok, true);
    const capture = browser.nativeCalls.find((c) => c.type === "capture");
    assert.equal(capture.imageData, "QUJD");
});

// ---------- content.js 用例 ----------

function makeContentSandbox({ scrollHeight, viewportHeight = 800 }) {
    const listeners = [];
    const state = { scrollY: 0 };
    const sandbox = {
        window: {
            innerWidth: 390,
            innerHeight: viewportHeight,
            devicePixelRatio: 3,
            scrollTo(x, y) {
                state.scrollY = Math.min(y, Math.max(0, scrollHeight - viewportHeight));
            },
            get scrollY() {
                return state.scrollY;
            }
        },
        document: {
            documentElement: {
                scrollWidth: 390,
                clientWidth: 390,
                scrollHeight,
                clientHeight: viewportHeight
            }
        },
        browser: {
            runtime: {
                onMessage: {
                    addListener(fn) {
                        listeners.push(fn);
                    }
                }
            }
        },
        setTimeout,
        dispatch(message) {
            return listeners[0](message, {});
        }
    };
    loadScript("content.js", sandbox);
    return sandbox;
}

await test("content.js page-metrics 上报页面尺寸", async () => {
    const sandbox = makeContentSandbox({ scrollHeight: 2400 });
    const metrics = await sandbox.dispatch({ type: "page-metrics" });
    assert.equal(metrics.height, 2400);
    assert.equal(metrics.viewportHeight, 800);
    assert.equal(metrics.devicePixelRatio, 3);
});

await test("content.js scroll-to 返回实际滚动位置与到底标记", async () => {
    const sandbox = makeContentSandbox({ scrollHeight: 2400 });
    const first = await sandbox.dispatch({ type: "scroll-to", y: 800, settle: 1 });
    assert.equal(first.scrollY, 800);
    assert.equal(first.reachedBottom, false);

    const second = await sandbox.dispatch({ type: "scroll-to", y: 9999, settle: 1 });
    assert.equal(second.scrollY, 1600); // 钳制到最大可滚动位置
    assert.equal(second.reachedBottom, true);
});

// ---------- 配置静态校验 ----------

await test("manifest.json 合法且引用存在的资源", async () => {
    const manifest = JSON.parse(readFileSync(path.join(safariDir, "manifest.json"), "utf8"));
    assert.equal(manifest.manifest_version, 2);
    for (const script of manifest.background.scripts) {
        readFileSync(path.join(safariDir, script));
    }
    for (const cs of manifest.content_scripts) {
        for (const script of cs.js) {
            readFileSync(path.join(safariDir, script));
        }
    }
    readFileSync(path.join(safariDir, manifest.browser_action.default_popup));
    const popupHtml = readFileSync(path.join(safariDir, "popup.html"), "utf8");
    assert.match(popupHtml, /popup\.js/);
});

console.log(`\n${passed} 项通过${process.exitCode ? "，存在失败" : ""}`);
