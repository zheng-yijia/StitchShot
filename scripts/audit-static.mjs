// Swift 源码静态审计（无编译器环境下的近似检查）。
// 运行：node scripts/audit-static.mjs
import { readFileSync, readdirSync, statSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const findings = [];
function report(category, file, line, message) {
    findings.push({ category, file: path.relative(root, file), line, message });
}

function walk(dir, ext) {
    const out = [];
    for (const entry of readdirSync(dir)) {
        const full = path.join(dir, entry);
        if (statSync(full).isDirectory()) out.push(...walk(full, ext));
        else if (entry.endsWith(ext)) out.push(full);
    }
    return out;
}

const swiftFiles = [
    ...walk(path.join(root, "App"), ".swift"),
    ...walk(path.join(root, "Extensions"), ".swift"),
    ...walk(path.join(root, "Packages"), ".swift")
];

// ---------- 词法：剥离注释与字符串字面量 ----------

function stripCommentsAndStrings(code) {
    let out = "";
    let i = 0;
    let blockDepth = 0;
    while (i < code.length) {
        const two = code.slice(i, i + 2);
        const three = code.slice(i, i + 3);
        if (blockDepth > 0) {
            if (two === "/*") { blockDepth += 1; i += 2; continue; }
            if (two === "*/") { blockDepth -= 1; i += 2; continue; }
            i += 1;
            continue;
        }
        if (two === "//") {
            while (i < code.length && code[i] !== "\n") i += 1;
            continue;
        }
        if (two === "/*") { blockDepth = 1; i += 2; continue; }
        if (three === '"""') {
            i += 3;
            while (i < code.length && code.slice(i, i + 3) !== '"""') i += 1;
            i += 3;
            continue;
        }
        if (code[i] === '"') {
            i += 1;
            while (i < code.length && code[i] !== '"') {
                if (code[i] === "\\") i += 1;
                i += 1;
            }
            i += 1;
            continue;
        }
        out += code[i];
        i += 1;
    }
    return out;
}

// ---------- A. 括号平衡 ----------

for (const file of swiftFiles) {
    const stripped = stripCommentsAndStrings(readFileSync(file, "utf8"));
    const counts = { "{": 0, "(": 0, "[": 0 };
    const close = { "}": "{", ")": "(", "]": "[" };
    for (const ch of stripped) {
        if (ch in counts) counts[ch] += 1;
        else if (ch in close) counts[close[ch]] -= 1;
    }
    if (counts["{"] !== 0 || counts["("] !== 0 || counts["["] !== 0) {
        report("brace-balance", file, "-", `不平衡 {}=${counts["{"]} ()=${counts["("]} []=${counts["["]}`);
    }
}

// ---------- B. iOS 15 API 可用性 ----------

const ios16SwiftUI = [
    "NavigationStack", "NavigationSplitView", "PhotosPicker", "ViewThatFits",
    "presentationDetents", "scrollDismissesKeyboard", "LabeledContent", "ShareLink",
    "GridRow", "scrollIndicators", "scrollTargetBehavior", "contentMargins"
];
const ios17Plus = ["symbolEffect", "contentTransition", "scrollTargetLayout", "onScrollGeometryChange", "containerRelativeFrame"];

for (const file of swiftFiles) {
    const raw = readFileSync(file, "utf8");
    const lines = raw.split("\n");
    for (const [index, line] of lines.entries()) {
        for (const sym of ios16SwiftUI) {
            if (line.includes(sym)) report("ios16-api", file, index + 1, `iOS 16+ SwiftUI API: ${sym}`);
        }
        for (const sym of ios17Plus) {
            if (line.includes(sym)) report("ios17-api", file, index + 1, `iOS 17+ API: ${sym}`);
        }
    }
    // AppIntents：需要 @available(iOS 16+ 或处于 iOS18-only 的 canImport(ControlCenter) 块
    const usesAppIntents = ["AppShortcutsProvider", "AppShortcut(", "AppEnum", "IntentFile", "IntentDescription", "@Parameter", "IntentResult"]
        .some((s) => raw.includes(s));
    if (usesAppIntents && !/@available\(iOS (1[6-9]|\d{2,})/.test(raw) && !raw.includes("canImport(ControlCenter)")) {
        report("unguarded-api", file, "-", "AppIntents(iOS16+) 使用但缺少可用性守卫");
    }
    const usesControl = ["ControlWidget", "StaticControlConfiguration", "ControlWidgetButton"].some((s) => raw.includes(s));
    if (usesControl && !raw.includes("canImport(ControlCenter)")) {
        report("unguarded-api", file, "-", "ControlCenter(iOS18+) 使用但缺少 canImport 守卫");
    }
}

// ---------- C. import 完整性 ----------

const importRules = [
    { use: /\bUIImage|\bUIColor|\bUIFont|UIGraphics/, need: /import (UIKit|SwiftUI)/, name: "UIKit" },
    { use: /\bPHAsset|\bPHPhotoLibrary|\bPHFetchResult|\bPHImageRequestOptions/, need: /import Photos/, name: "Photos" },
    { use: /\bProduct\.products|\bAppStore\.sync|VerificationResult/, need: /import StoreKit/, name: "StoreKit" },
    { use: /RPBroadcast|RPSystemBroadcastPickerView|RPScreenRecorder/, need: /import ReplayKit/, name: "ReplayKit" },
    { use: /CMSampleBuffer|CMGetAttachment/, need: /import CoreMedia|import AVFoundation/, name: "CoreMedia" },
    { use: /\bCIImage|\bCIFilter|\bCIContext|\bCIVector/, need: /import CoreImage/, name: "CoreImage" },
    { use: /\bLivePhotoConverter\b|\bLivePhotoOptions\b|\bLivePhotoResult\b|\bLivePhotoLoopMode\b/, need: /import LivePhotoKit/, name: "LivePhotoKit", ownDir: "Sources/LivePhotoKit" },
    { use: /UTType\.image/, need: /import UniformTypeIdentifiers|import CoreServices/, name: "UniformTypeIdentifiers" },
    { use: /TimelineProvider|WidgetBundle/, need: /import WidgetKit/, name: "WidgetKit" },
    { use: /VNTranslationalImageRegistration|VNImageRequestHandler/, need: /import Vision/, name: "Vision" }
];

for (const file of swiftFiles) {
    const raw = readFileSync(file, "utf8");
    const code = stripCommentsAndStrings(raw);
    const normalized = file.replace(/\\/g, "/");
    for (const rule of importRules) {
        if (rule.ownDir && normalized.includes(rule.ownDir)) continue;
        if (rule.use.test(code) && !rule.need.test(raw)) {
            report("missing-import", file, "-", `使用了 ${rule.name} 符号但未 import`);
        }
    }
}

// ---------- D. 跨模块 API 一致性（仅校验 类型名.成员 限定调用，支持默认参数与尾闭包） ----------

// 收集包内 public 类型及其 static func 签名
const pkgFiles = walk(path.join(root, "Packages", "StitchKit", "Sources"), ".swift");
const appAndExt = [
    ...walk(path.join(root, "App"), ".swift"),
    ...walk(path.join(root, "Extensions"), ".swift")
];

// typeName -> { funcName -> [{ required: [], optional: [] }] }
const typeDecls = new Map();

for (const file of pkgFiles) {
    const stripped = stripCommentsAndStrings(readFileSync(file, "utf8"));
    const typeRe = /public\s+(?:final\s+)?(?:struct|enum|class)\s+(\w+)/g;
    let tm;
    while ((tm = typeRe.exec(stripped))) {
        const typeName = tm[1];
        // 在类型声明之后扫描 public static func（近似：到下一个 public 类型或文件尾）
        const rest = stripped.slice(tm.index);
        const nextType = rest.slice(10).search(/public\s+(?:final\s+)?(?:struct|enum|class)\s+\w+/);
        const scope = nextType === -1 ? rest : rest.slice(0, nextType + 10);
        const funcRe = /public\s+static\s+func\s+(\w+)\s*\(/g;
        let fm;
        while ((fm = funcRe.exec(scope))) {
            const funcName = fm[1];
            let depth = 0;
            let j = scope.indexOf("(", fm.index);
            const start = j;
            for (; j < scope.length; j++) {
                if (scope[j] === "(") depth += 1;
                else if (scope[j] === ")") { depth -= 1; if (depth === 0) break; }
            }
            const params = splitTopLevel(scope.slice(start + 1, j)).map((p) => {
                const head = p.split(":")[0].trim().split(/\s+/);
                return { label: head[0] === "_" ? "" : head[0], hasDefault: /:(?:[^=])*=/.test(p) };
            });
            if (!typeDecls.has(typeName)) typeDecls.set(typeName, new Map());
            const funcs = typeDecls.get(typeName);
            if (!funcs.has(funcName)) funcs.set(funcName, []);
            funcs.get(funcName).push(params);
        }
    }
}

function splitTopLevel(text) {
    const parts = [];
    let depth = 0;
    let cur = "";
    for (const ch of text) {
        if ("([{<".includes(ch)) depth += 1;
        if (")]}>".includes(ch)) depth -= 1;
        if (ch === "," && depth === 0) { parts.push(cur); cur = ""; continue; }
        cur += ch;
    }
    if (cur.trim()) parts.push(cur);
    return parts.filter((p) => p.trim());
}

function callLabelsAt(text, openIndex) {
    let depth = 0;
    let j = openIndex;
    for (; j < text.length; j++) {
        if (text[j] === "(") depth += 1;
        else if (text[j] === ")") { depth -= 1; if (depth === 0) break; }
    }
    return splitTopLevel(text.slice(openIndex + 1, j)).map((p) => {
        const m = /^\s*(\w+)\s*:/.exec(p);
        return m ? m[1] : "";
    });
}

for (const file of appAndExt) {
    const stripped = stripCommentsAndStrings(readFileSync(file, "utf8"));
    for (const [typeName, funcs] of typeDecls) {
        for (const [funcName, decls] of funcs) {
            const re = new RegExp(`\\b${typeName}\\.${funcName}\\(`, "g");
            let m;
            while ((m = re.exec(stripped))) {
                const openIndex = m.index + typeName.length + 1 + funcName.length;
                const labels = callLabelsAt(stripped, openIndex);
                const ok = decls.some((params) => {
                    if (labels.length > params.length) return false;
                    return labels.every((label, i) => params[i].label === "" || params[i].label === label)
                        && params.slice(labels.length).every((p) => p.hasDefault);
                });
                if (!ok) {
                    const line = stripped.slice(0, m.index).split("\n").length;
                    report("api-mismatch", file, line,
                        `${typeName}.${funcName}(${labels.join(":")}) 与声明不符 (${decls.map((d) => d.map((p) => p.label + (p.hasDefault ? "=?" : "")).join(":")).join(" | ")})`);
                }
            }
        }
    }
}

// ---------- E. 配置一致性（bundle id / App Group / URL scheme） ----------

const allTextFiles = [
    ...swiftFiles,
    path.join(root, "project.yml"),
    ...walk(path.join(root, "Extensions", "Safari", "Resources"), ".js")
];

const groups = new Set();
const bundleIds = new Set();
for (const file of allTextFiles) {
    let raw = "";
    try { raw = readFileSync(file, "utf8"); } catch { continue; }
    for (const m of raw.matchAll(/group\.com\.[a-z0-9.]+/g)) groups.add(m[0]);
    for (const m of raw.matchAll(/com\.example\.stitchshot[\w.]*/g)) bundleIds.add(m[0]);
}
const badGroups = [...groups].filter((g) => g !== "group.com.example.stitchshot");
if (badGroups.length) report("config", "(多处)", "-", `异常 App Group: ${badGroups.join(", ")}`);
const expectedIds = new Set([
    "com.example.stitchshot",
    "com.example.stitchshot.StitchShotBroadcast",
    "com.example.stitchshot.control.scrollcapture",
    "com.example.stitchshot.pro",
    "com.example.stitchshot.quickactions",
    "com.example.stitchshot.url"
]);
const badIds = [...bundleIds].filter((b) => !expectedIds.has(b));
if (badIds.length) report("config", "(多处)", "-", `异常 bundle id: ${badIds.join(", ")}`);

// URL scheme：project.yml 声明、AppConstants、小组件/扩展使用应一致
const projectYml = readFileSync(path.join(root, "project.yml"), "utf8");
const schemeDeclared = /CFBundleURLSchemes:[\s\S]*?-\s*(\w+)/.exec(projectYml)?.[1];
const appConstants = readFileSync(path.join(root, "Packages/StitchKit/Sources/StitchCore/AppConstants.swift"), "utf8");
const schemeInCode = /urlScheme\s*=\s*"(\w+)"/.exec(appConstants)?.[1];
if (schemeDeclared !== schemeInCode) {
    report("config", "project.yml", "-", `URL scheme 不一致: yml=${schemeDeclared} code=${schemeInCode}`);
}

// ---------- F. 已知非法参数标签（编译报错类） ----------

// Toggle/Slider/Stepper/TextField/Picker 没有 isPresented: 初始化器
const badLabel = /\b(Toggle|Slider|Stepper|TextField|Picker)\s*\(\s*(?:"[^"]*"|[A-Za-z_][\w.]*)?\s*,?\s*isPresented\s*:/g;
for (const file of swiftFiles) {
    const stripped = stripCommentsAndStrings(readFileSync(file, "utf8"));
    for (const m of stripped.matchAll(badLabel)) {
        const line = stripped.slice(0, m.index).split("\n").length;
        report("bad-label", file, line, `${m[1]} 使用了不存在的 isPresented: 参数（应为 isOn:/value: 等）`);
    }
}

// ---------- 输出 ----------

if (findings.length === 0) {
    console.log("静态审计通过：无发现");
} else {
    for (const f of findings) {
        console.log(`[${f.category}] ${f.file}:${f.line} ${f.message}`);
    }
    console.log(`\n共 ${findings.length} 项发现`);
}
process.exit(findings.length ? 1 : 0);
