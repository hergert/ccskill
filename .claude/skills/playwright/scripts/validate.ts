#!/usr/bin/env bun
/**
 * validate.ts — Run a Playwright validation script with structured results.
 *
 * Usage:
 *   bun run scripts/validate.ts <script.ts> [--output-dir results/] [--timeout 15000]
 *
 * The target script must export:
 *   - validate(page: Page): Promise<{ message?: string } | void>
 *   - URL?: string          (optional, auto-navigated)
 *   - VIEWPORT?: object     (optional, default 1280x720)
 *   - WAIT_UNTIL?: string   (optional, default domcontentloaded)
 *
 * Example target (check_login.ts):
 *
 *   import type { Page } from "playwright";
 *   export const URL = "http://localhost:3000/login";
 *   export async function validate(page: Page) {
 *     await page.getByLabel("Email").fill("test@example.com");
 *     await page.getByLabel("Password").fill("password");
 *     await page.getByRole("button", { name: "Sign in" }).click();
 *     await page.waitForURL("**/dashboard", { timeout: 5000 });
 *     const welcome = page.getByText("Welcome");
 *     if (!(await welcome.isVisible())) throw new Error("No welcome message");
 *     return { message: "Login works" };
 *   }
 *
 * Output: JSON with status (pass|fail|error), timing, screenshots, errors.
 */

import { chromium } from "playwright";
import { parseArgs } from "util";
import { mkdirSync, existsSync } from "fs";
import { resolve, basename } from "path";

const { values, positionals } = parseArgs({
  args: Bun.argv.slice(2),
  options: {
    "output-dir": { type: "string", short: "o", default: "results" },
    timeout:      { type: "string", short: "t", default: "15000" },
    help:         { type: "boolean", short: "h", default: false },
  },
  allowPositionals: true,
  strict: false,
});

if (values.help || positionals.length === 0) {
  console.log(`Usage: bun run validate.ts <script.ts> [-o results/] [-t 15000]`);
  process.exit(0);
}

const scriptPath = resolve(positionals[0]);
const outputDir = values["output-dir"] as string;
const timeoutMs = parseInt(values.timeout as string, 10);

async function safeScreenshot(page: any, path: string) {
  try { await page.screenshot({ path, fullPage: false }); } catch {}
}

async function main() {
  const target = await import(scriptPath);

  if (typeof target.validate !== "function") {
    console.log(JSON.stringify({
      status: "error",
      error: `Script must export a validate(page) function`,
    }));
    process.exit(1);
  }

  const url = target.URL as string | undefined;
  const viewport = target.VIEWPORT ?? { width: 1280, height: 720 };
  const waitUntil = target.WAIT_UNTIL ?? "domcontentloaded";

  if (!existsSync(outputDir)) mkdirSync(outputDir, { recursive: true });

  const result: Record<string, any> = {
    status: "pass",
    script: basename(scriptPath),
    screenshots: {},
    timing: {},
  };

  const consoleErrors: string[] = [];
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ viewport });
  const page = await context.newPage();
  page.setDefaultTimeout(timeoutMs);

  page.on("console", (msg) => {
    if (msg.type() === "error") consoleErrors.push(msg.text());
  });

  // Navigate
  if (url) {
    try {
      const start = performance.now();
      await page.goto(url, { waitUntil, timeout: timeoutMs });
      result.timing.navigation_ms = Math.round(performance.now() - start);
    } catch (e: any) {
      result.status = "error";
      result.error = `Navigation failed: ${e.message?.slice(0, 300)}`;
      await safeScreenshot(page, resolve(outputDir, "error.png"));
      result.screenshots.error = resolve(outputDir, "error.png");
      await browser.close();
      console.log(JSON.stringify(result, null, 2));
      process.exit(1);
    }
  }

  // Before screenshot
  await safeScreenshot(page, resolve(outputDir, "before.png"));
  result.screenshots.before = resolve(outputDir, "before.png");

  // Run validation
  const start = performance.now();
  try {
    const ret = await target.validate(page);
    result.timing.validation_ms = Math.round(performance.now() - start);
    result.message = ret?.message ?? "Validation passed";
  } catch (e: any) {
    result.timing.validation_ms = Math.round(performance.now() - start);
    const isAssertion = e.name === "AssertionError" || e.message?.includes("assert") || e.constructor?.name?.includes("Assert");
    result.status = isAssertion ? "fail" : "error";
    result.error = e.message?.slice(0, 500) ?? String(e);
    result.traceback = e.stack?.split("\n").slice(0, 5).join("\n");
  }

  // After screenshot
  await safeScreenshot(page, resolve(outputDir, "after.png"));
  result.screenshots.after = resolve(outputDir, "after.png");

  if (consoleErrors.length) result.console_errors = consoleErrors.slice(0, 10);
  result.final_url = page.url();

  await browser.close();
  console.log(JSON.stringify(result, null, 2));
  process.exit(result.status === "pass" ? 0 : 1);
}

main().catch((e) => {
  console.log(JSON.stringify({ status: "error", error: String(e) }));
  process.exit(1);
});
