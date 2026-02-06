/**
 * helpers.ts — Reusable Playwright helpers for custom scripts.
 *
 * Import in your scripts:
 *   import { withBrowser, navigateAndWait, screenshotPage } from "./scripts/helpers.ts";
 *
 * Or from /tmp scripts (adjust path to skill location):
 *   import { withBrowser } from "<project>/.claude/skills/playwright-ui-validator/scripts/helpers.ts";
 */

import { chromium, type Page, type BrowserContext } from "playwright";

// --- Types ---

export interface BrowserOptions {
  width?: number;
  height?: number;
  colorScheme?: "light" | "dark" | "no-preference";
  deviceScaleFactor?: number;
  locale?: string;
  userAgent?: string;
}

const DEFAULTS: Required<Pick<BrowserOptions, "width" | "height" | "deviceScaleFactor">> = {
  width: 1280,
  height: 720,
  deviceScaleFactor: 2, // retina-quality screenshots
};

// --- Core ---

/**
 * Launch headless Chromium, create a page, run your function, then cleanup.
 *
 * Usage:
 *   await withBrowser(async (page) => {
 *     await navigateAndWait(page, "http://localhost:3000");
 *     await screenshotPage(page, "/tmp/pw-home.png");
 *   });
 */
export async function withBrowser(
  fn: (page: Page, context: BrowserContext) => Promise<void>,
  opts: BrowserOptions = {}
): Promise<void> {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({
    viewport: {
      width: opts.width ?? DEFAULTS.width,
      height: opts.height ?? DEFAULTS.height,
    },
    deviceScaleFactor: opts.deviceScaleFactor ?? DEFAULTS.deviceScaleFactor,
    colorScheme: opts.colorScheme,
    locale: opts.locale,
    userAgent: opts.userAgent,
  });
  const page = await context.newPage();

  try {
    await fn(page, context);
  } finally {
    await browser.close();
  }
}

/**
 * Navigate and wait for page to be ready.
 * Uses domcontentloaded (fast, reliable) + optional locator wait.
 *
 * Usage:
 *   await navigateAndWait(page, "http://localhost:3000");
 *   await navigateAndWait(page, "http://localhost:3000", ".my-component");
 */
export async function navigateAndWait(
  page: Page,
  url: string,
  waitForSelector?: string,
  timeout = 15000
): Promise<void> {
  await page.goto(url, { waitUntil: "domcontentloaded", timeout });
  if (waitForSelector) {
    await page.locator(waitForSelector).waitFor({ state: "visible", timeout });
  }
}

/**
 * Full-page or viewport screenshot.
 */
export async function screenshotPage(
  page: Page,
  path: string,
  fullPage = false
): Promise<void> {
  const { mkdirSync, existsSync } = await import("fs");
  const { dirname } = await import("path");
  const dir = dirname(path);
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
  await page.screenshot({ path, fullPage });
}

/**
 * Screenshot a specific element by CSS selector.
 */
export async function screenshotElement(
  page: Page,
  selector: string,
  path: string,
  timeout = 5000
): Promise<void> {
  const { mkdirSync, existsSync } = await import("fs");
  const { dirname } = await import("path");
  const dir = dirname(path);
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
  await page.locator(selector).waitFor({ state: "visible", timeout });
  await page.locator(selector).screenshot({ path });
}

/**
 * Extract visible text from all elements matching a selector.
 * Returns trimmed, non-empty strings.
 *
 * Usage:
 *   const words = await extractText(page, ".word-stripe__svg text");
 */
export async function extractText(
  page: Page,
  selector: string,
  timeout = 5000
): Promise<string[]> {
  await page.locator(selector).first().waitFor({ state: "attached", timeout });
  const texts = await page.$eval(selector, (els) =>
    els.map((el) => (el.textContent ?? "").trim()).filter(Boolean)
  );
  return texts;
}

/**
 * Collect page metadata: URL, title, element counts.
 */
export async function getPageInfo(page: Page): Promise<Record<string, any>> {
  return {
    url: page.url(),
    title: await page.title(),
    elements: {
      buttons: await page.locator("button, [role='button']").count(),
      inputs: await page.locator("input:not([type='hidden']), textarea, select").count(),
      links: await page.locator("a[href]").count(),
      images: await page.locator("img").count(),
    },
  };
}
