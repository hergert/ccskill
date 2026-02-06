---
name: playwright-ui-validator
description: >
  Browser automation for UI validation — screenshots, content extraction, interaction
  testing, responsive checks. Use when asked to test, verify, validate, screenshot,
  check, or interact with a web application, website, UI, frontend, page, form, or
  any browser-based interface. Also triggers for: responsive layout checks, visual
  regression, extracting rendered text, dark mode testing, locale/i18n verification,
  component screenshots. User-initiated — do NOT invoke automatically unless the user
  explicitly requests browser interaction. Requires bun runtime and playwright.
---

# Playwright UI Validator

Headless Chromium browser automation via Bun + TypeScript. Two modes: quick CLI tools and custom scripts using helpers.

## Setup (once per environment)

```bash
bash scripts/setup.sh
```

## Decision Tree

When the user asks for browser work, pick the right approach:

- **URL given** → `snap.ts` for full-page screenshot
- **Component name** → look up selector in [references/selectors.md](references/selectors.md) → element screenshot with `-s`
- **"extract" / "get text"** → write a short script using `helpers.ts` → `extractText()`
- **"responsive" / "mobile"** → `snap.ts` with `-v 375x812` or `-d "iPhone 13"`
- **"dark mode"** → custom script with `withBrowser({ colorScheme: "dark" })`
- **"all locales" / "i18n"** → custom script looping locales with `helpers.ts`
- **Multi-step flow** (login, CRUD, form) → `validate.ts` with a validation script
- **One-off interaction** → `snap.ts` with `-a` actions

## CRITICAL: Always View Screenshots

After every screenshot capture, **immediately view the image file** to understand what the browser shows. Never assume a screenshot succeeded — look at it, then decide the next step. This is the core feedback loop: **See → Act → Verify**.

## Mode 1: Quick CLI (snap.ts)

```bash
# Full-page screenshot
bun run scripts/snap.ts http://localhost:3000 -o snap.png

# Element screenshot
bun run scripts/snap.ts http://localhost:3000 -s ".word-stripe" -o component.png

# With interactions
bun run scripts/snap.ts http://localhost:3000 -a 'fill:#email=test@test.com' 'click:#submit' -o result.png

# Mobile viewport
bun run scripts/snap.ts http://localhost:3000 -v 375x812 -o mobile.png

# Device emulation
bun run scripts/snap.ts http://localhost:3000 -d "iPhone 13" -o iphone.png
```

**Actions** (`-a`): `click:<sel>`, `fill:<sel>=<val>`, `select:<sel>=<val>`, `check:<sel>`, `hover:<sel>`, `press:<key>`, `wait:<ms>`, `goto:<url>`, `scroll:<sel>`, `type:<sel>=<val>`

Outputs JSON to stdout (title, URL, element counts, console errors) + saves PNG.

## Mode 2: Custom Scripts (helpers.ts)

For anything beyond snap.ts — extraction, loops, multi-step flows — write a short script importing from helpers:

```ts
import { withBrowser, navigateAndWait, screenshotPage } from "./scripts/helpers.ts";

await withBrowser(async (page) => {
  await navigateAndWait(page, "http://localhost:3000");
  await screenshotPage(page, "/tmp/pw-home.png");
}, { width: 1280, height: 720 });
```

Write scripts to `/tmp/pw-*.ts`, run with `bun run /tmp/pw-<name>.ts`.

### helpers.ts exports

| Function | Purpose |
|---|---|
| `withBrowser(fn, opts?)` | Launch Chromium, create page, run fn(page), cleanup. Options: `width`, `height`, `colorScheme`, `deviceScaleFactor` |
| `navigateAndWait(page, url, selector?)` | goto + domcontentloaded + optional locator wait (NOT networkidle) |
| `screenshotPage(page, path, fullPage?)` | Full or viewport screenshot |
| `screenshotElement(page, selector, path)` | Wait for selector, screenshot element |
| `extractText(page, selector)` | querySelectorAll → trimmed text array |

### Example: extract text across locales

```ts
import { withBrowser, navigateAndWait, extractText } from "./scripts/helpers.ts";

const locales = ["it", "en", "de"];
await withBrowser(async (page) => {
  for (const locale of locales) {
    await navigateAndWait(page, `http://localhost:3000/${locale}`, ".word-stripe");
    const words = await extractText(page, ".word-stripe__svg text");
    console.log(`${locale}:`, words);
  }
});
```

### Example: dark mode comparison

```ts
import { withBrowser, navigateAndWait, screenshotPage } from "./scripts/helpers.ts";

for (const scheme of ["light", "dark"] as const) {
  await withBrowser(async (page) => {
    await navigateAndWait(page, "http://localhost:3000");
    await screenshotPage(page, `/tmp/pw-${scheme}.png`);
  }, { colorScheme: scheme });
}
```

## Mode 3: Structured Validation (validate.ts)

For repeatable multi-step assertions:

```ts
import type { Page } from "playwright";
export const URL = "http://localhost:3000/login";

export async function validate(page: Page) {
  await page.getByLabel("Email").fill("test@example.com");
  await page.getByLabel("Password").fill("password");
  await page.getByRole("button", { name: "Sign in" }).click();
  await page.waitForURL("**/dashboard", { timeout: 5000 });
  if (!(await page.getByText("Welcome").isVisible()))
    throw new Error("No welcome message");
  return { message: "Login works" };
}
```

```bash
bun run scripts/validate.ts check_login.ts -o results/
```

Returns JSON: `status` (pass/fail/error), timing, before+after screenshots.

## Locator Priority

1. `page.getByRole("button", { name: "Submit" })` — best
2. `page.getByLabel("Email")` — form fields
3. `page.getByText("Welcome")` — visible text
4. `page.getByTestId("submit-btn")` — needs `data-testid`
5. `page.locator(".my-class")` — CSS fallback, check [references/selectors.md](references/selectors.md) first

Chain: `page.locator(".card").filter({ hasText: "Product" }).getByRole("button", { name: "Buy" })`

## More Patterns

For ready-to-use validation scripts (forms, auth, CRUD, responsive, API mocking, toasts, modals, a11y), see [references/patterns.md](references/patterns.md).

## Troubleshooting

- **Element not found**: Screenshot first, view it. Use `await page.content()` to inspect HTML.
- **Timeout**: Use locator `.waitFor()` instead of hardcoded waits. Check app is running.
- **Flaky clicks**: Prefer `getByRole` over CSS. Add `wait:500` before interaction if needed.
- **Auth required**: Use `-c` cookies in snap.ts, or `page.context().addCookies([...])` in scripts.
- **Console errors**: snap.ts captures them in JSON stdout.
