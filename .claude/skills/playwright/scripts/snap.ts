#!/usr/bin/env bun
/**
 * snap.ts — Browser screenshot & interaction tool for Claude Code.
 *
 * Usage:
 *   bun run scripts/snap.ts <URL> [options]
 *
 * Examples:
 *   bun run scripts/snap.ts http://localhost:3000
 *   bun run scripts/snap.ts http://localhost:3000 -o login.png
 *   bun run scripts/snap.ts http://localhost:3000 -a 'click:#btn' 'fill:#email=test@test.com'
 *   bun run scripts/snap.ts http://localhost:3000 --viewport 375x812
 *   bun run scripts/snap.ts http://localhost:3000 --device "iPhone 13"
 *   bun run scripts/snap.ts http://localhost:3000 --selector "#login-form"
 *   bun run scripts/snap.ts http://localhost:3000 --full-page
 *
 * Action syntax (-a / --actions):
 *   click:<selector>              Click element
 *   fill:<selector>=<value>       Fill input
 *   select:<selector>=<value>     Select dropdown option
 *   check:<selector>              Check checkbox
 *   hover:<selector>              Hover element
 *   press:<key>                   Keyboard key (Enter, Tab, Escape...)
 *   wait:<ms>                     Wait milliseconds
 *   goto:<url>                    Navigate to URL
 *   scroll:<selector>             Scroll element into view
 *   type:<selector>=<value>       Type character by character (slow fill)
 *
 * Output: PNG screenshot + JSON summary to stdout.
 */

import { chromium, devices, type Page } from "playwright";
import { parseArgs } from "util";
import { mkdirSync, existsSync } from "fs";
import { dirname, resolve } from "path";

// --- Arg parsing ---

const { values, positionals } = parseArgs({
  args: Bun.argv.slice(2),
  options: {
    output:     { type: "string", short: "o", default: ".claude/skills/playwright/.snaps/screenshot.png" },
    selector:   { type: "string", short: "s" },
    actions:    { type: "string", short: "a", multiple: true },
    viewport:   { type: "string", short: "v", default: "1280x720" },
    "full-page":{ type: "boolean", short: "f", default: false },
    device:     { type: "string", short: "d" },
    cookies:    { type: "string", short: "c" },
    wait:       { type: "string", short: "w", default: "domcontentloaded" },
    timeout:    { type: "string", short: "t", default: "15000" },
    "no-info":  { type: "boolean", default: false },
    help:       { type: "boolean", short: "h", default: false },
  },
  allowPositionals: true,
  strict: false,
});

if (values.help || positionals.length === 0) {
  console.log(`Usage: bun run snap.ts <URL> [options]
  -o, --output <file>       Screenshot path (default: screenshot.png)
  -s, --selector <sel>      Screenshot only this element
  -a, --actions <action...> Actions before screenshot
  -v, --viewport <WxH>      Viewport size (default: 1280x720)
  -f, --full-page           Full page screenshot
  -d, --device <name>       Device emulation (e.g. "iPhone 13")
  -c, --cookies <json>      Cookies JSON to set
  -w, --wait <event>        Wait: load|domcontentloaded|networkidle|commit
  -t, --timeout <ms>        Navigation timeout (default: 15000)
      --no-info             Skip page info, only screenshot
  -h, --help                Show help`);
  process.exit(0);
}

const url = positionals[0];
const outputPath = values.output as string;
const timeoutMs = parseInt(values.timeout as string, 10);

// --- Action execution ---

interface ActionResult {
  action: string;
  status: "ok" | "error";
  message?: string;
}

async function executeAction(page: Page, raw: string): Promise<ActionResult> {
  const colonIdx = raw.indexOf(":");
  if (colonIdx === -1) return { action: raw, status: "error", message: "Invalid format. Use verb:target" };

  const verb = raw.slice(0, colonIdx).trim().toLowerCase();
  const rest = raw.slice(colonIdx + 1).trim();

  let target = rest;
  let value: string | undefined;

  if (["fill", "select", "type"].includes(verb) && rest.includes("=")) {
    const eqIdx = rest.indexOf("=");
    target = rest.slice(0, eqIdx);
    value = rest.slice(eqIdx + 1);
  }

  try {
    switch (verb) {
      case "click":   await page.locator(target).click({ timeout: 5000 }); break;
      case "fill":    await page.locator(target).fill(value ?? "", { timeout: 5000 }); break;
      case "type":    await page.locator(target).pressSequentially(value ?? "", { delay: 50, timeout: 5000 }); break;
      case "select":  await page.locator(target).selectOption(value ?? "", { timeout: 5000 }); break;
      case "check":   await page.locator(target).check({ timeout: 5000 }); break;
      case "hover":   await page.locator(target).hover({ timeout: 5000 }); break;
      case "press":   await page.keyboard.press(target); break;
      case "wait":    await page.waitForTimeout(parseInt(target, 10)); break;
      case "goto":    await page.goto(target, { waitUntil: "domcontentloaded" }); break;
      case "scroll":  await page.locator(target).scrollIntoViewIfNeeded({ timeout: 5000 }); break;
      default: return { action: raw, status: "error", message: `Unknown verb: ${verb}` };
    }
    return { action: raw, status: "ok" };
  } catch (e: any) {
    return { action: raw, status: "error", message: e.message?.slice(0, 200) };
  }
}

// --- Page info ---

async function collectPageInfo(page: Page) {
  const info: Record<string, any> = {
    url: page.url(),
    title: await page.title(),
  };

  try {
    const text = await page.locator("body").innerText({ timeout: 2000 });
    info.body_text_preview = text.slice(0, 500) + (text.length > 500 ? "..." : "");
  } catch { info.body_text_preview = ""; }

  try {
    info.element_counts = {
      buttons: await page.locator("button, [role='button'], input[type='submit']").count(),
      inputs:  await page.locator("input:not([type='hidden']), textarea, select").count(),
      links:   await page.locator("a[href]").count(),
      images:  await page.locator("img").count(),
      forms:   await page.locator("form").count(),
    };
  } catch { info.element_counts = {}; }

  return info;
}

// --- Main ---

async function main() {
  const [vw, vh] = (values.viewport as string).split("x").map(Number);
  const consoleMessages: { type: string; text: string }[] = [];
  const errors: string[] = [];

  const browser = await chromium.launch({ headless: true });

  let contextOpts: Record<string, any> = {};
  const deviceName = values.device as string | undefined;
  if (deviceName && devices[deviceName]) {
    contextOpts = { ...devices[deviceName] };
  } else {
    if (deviceName) errors.push(`Unknown device "${deviceName}", using custom viewport`);
    contextOpts = { viewport: { width: vw, height: vh } };
  }

  const context = await browser.newContext(contextOpts);

  if (values.cookies) {
    let cookies = JSON.parse(values.cookies as string);
    if (!Array.isArray(cookies)) cookies = [cookies];
    await context.addCookies(cookies);
  }

  const page = await context.newPage();
  page.on("console", (msg) => consoleMessages.push({ type: msg.type(), text: msg.text() }));
  page.on("pageerror", (err) => errors.push(String(err)));

  try {
    await page.goto(url, {
      waitUntil: values.wait as "load" | "domcontentloaded" | "networkidle" | "commit",
      timeout: timeoutMs,
    });
  } catch (e: any) {
    errors.push(`Navigation: ${e.message?.slice(0, 200)}`);
  }

  const actionResults: ActionResult[] = [];
  if (values.actions) {
    for (const a of values.actions as string[]) {
      actionResults.push(await executeAction(page, a));
    }
  }

  const dir = dirname(resolve(outputPath));
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });

  try {
    if (values.selector) {
      await page.locator(values.selector as string).screenshot({ path: outputPath, timeout: 5000 });
    } else {
      await page.screenshot({ path: outputPath, fullPage: values["full-page"] as boolean });
    }
  } catch (e: any) {
    errors.push(`Screenshot: ${e.message?.slice(0, 200)}`);
    try { await page.screenshot({ path: outputPath, fullPage: true }); } catch {}
  }

  const result: Record<string, any> = { screenshot: resolve(outputPath) };
  if (!values["no-info"]) result.page = await collectPageInfo(page);
  if (actionResults.length) result.actions = actionResults;
  if (errors.length) result.errors = errors;

  const consoleErrors = consoleMessages.filter((m) => m.type === "error" || m.type === "warning");
  if (consoleErrors.length) result.console_issues = consoleErrors.slice(0, 10);

  await browser.close();
  console.log(JSON.stringify(result, null, 2));
}

main().catch((e) => {
  console.log(JSON.stringify({ status: "error", error: String(e) }));
  process.exit(1);
});
