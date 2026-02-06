# Common Validation Patterns

All scripts below are standalone `.ts` files. Run with:
```bash
bun run scripts/validate.ts check_feature.ts --output-dir results/
```

## Form Validation

```ts
import type { Page } from "playwright";
export const URL = "http://localhost:3000/signup";

export async function validate(page: Page) {
  // Submit empty — expect required errors
  await page.getByRole("button", { name: "Submit" }).click();
  const errors = page.getByText("required");
  if ((await errors.count()) === 0) throw new Error("No required field errors shown");

  // Invalid email
  await page.getByLabel("Email").fill("not-an-email");
  await page.getByRole("button", { name: "Submit" }).click();
  if (!(await page.getByText("valid email").isVisible())) throw new Error("No email validation error");

  // Valid submission
  await page.getByLabel("Name").fill("Test User");
  await page.getByLabel("Email").fill("test@example.com");
  await page.getByLabel("Password").fill("SecurePass123!");
  await page.getByRole("button", { name: "Submit" }).click();
  await page.waitForURL("**/success**", { timeout: 5000 });
  return { message: "Form validation works" };
}
```

## Authentication Flow

```ts
import type { Page } from "playwright";
export const URL = "http://localhost:3000/login";

export async function validate(page: Page) {
  // Bad credentials
  await page.getByLabel("Email").fill("wrong@test.com");
  await page.getByLabel("Password").fill("wrong");
  await page.getByRole("button", { name: "Sign in" }).click();
  if (!(await page.getByText(/invalid|incorrect|error/i).isVisible({ timeout: 3000 })))
    throw new Error("No error for bad credentials");

  // Good credentials
  await page.getByLabel("Email").fill("user@test.com");
  await page.getByLabel("Password").fill("correct-password");
  await page.getByRole("button", { name: "Sign in" }).click();
  await page.waitForURL("**/dashboard**", { timeout: 5000 });
  if (page.url().includes("/login")) throw new Error("Still on login page");
  return { message: "Auth flow works" };
}
```

## Navigation & Routing

```ts
import type { Page } from "playwright";
export const URL = "http://localhost:3000";

export async function validate(page: Page) {
  const nav = page.locator("nav");
  if (!(await nav.isVisible())) throw new Error("Navigation not visible");

  const routes = [["About", "/about"], ["Contact", "/contact"]] as const;
  for (const [name, path] of routes) {
    await page.getByRole("link", { name }).click();
    await page.waitForURL(`**${path}**`, { timeout: 3000 });
    if (!page.url().includes(path)) throw new Error(`Did not navigate to ${path}`);
  }

  // 404
  await page.goto("http://localhost:3000/nonexistent-xyz");
  if (!(await page.getByText(/not found|404/i).isVisible({ timeout: 3000 })))
    throw new Error("No 404 page");
  return { message: "Navigation works" };
}
```

## Responsive Layout

Use snap.ts for visual checks at different viewports:

```bash
bun run scripts/snap.ts http://localhost:3000 --viewport 1920x1080 -o desktop.png
bun run scripts/snap.ts http://localhost:3000 --viewport 768x1024 -o tablet.png
bun run scripts/snap.ts http://localhost:3000 --viewport 375x812 -o mobile.png
bun run scripts/snap.ts http://localhost:3000 --device "iPhone 13" -o iphone.png
```

View each screenshot and verify layout adapts correctly.

## CRUD Operations

```ts
import type { Page } from "playwright";
export const URL = "http://localhost:3000/items";

export async function validate(page: Page) {
  // CREATE
  await page.getByRole("button", { name: "Add" }).click();
  await page.getByLabel("Name").fill("Test Item");
  await page.getByRole("button", { name: "Save" }).click();
  if (!(await page.getByText("Test Item").isVisible({ timeout: 3000 })))
    throw new Error("Created item not visible");

  // UPDATE
  await page.getByText("Test Item").click();
  await page.getByLabel("Name").fill("Updated Item");
  await page.getByRole("button", { name: "Save" }).click();
  if (!(await page.getByText("Updated Item").isVisible({ timeout: 3000 })))
    throw new Error("Updated item not visible");

  // DELETE
  await page.getByText("Updated Item").click();
  await page.getByRole("button", { name: "Delete" }).click();
  const confirm = page.getByRole("button", { name: "Confirm" });
  if (await confirm.isVisible({ timeout: 1000 })) await confirm.click();
  await page.waitForTimeout(500);
  if (await page.getByText("Updated Item").isVisible({ timeout: 2000 }).catch(() => false))
    throw new Error("Deleted item still visible");
  return { message: "CRUD works" };
}
```

## API Mocking

```ts
import type { Page } from "playwright";
export const URL = "http://localhost:3000/dashboard";

export async function validate(page: Page) {
  // Mock before navigation
  await page.route("**/api/users", (route) =>
    route.fulfill({ json: [{ id: 1, name: "Mock User" }] })
  );
  await page.goto(URL, { waitUntil: "networkidle" });
  if (!(await page.getByText("Mock User").isVisible({ timeout: 3000 })))
    throw new Error("Mocked data not rendered");

  // Error state
  await page.route("**/api/users", (route) =>
    route.fulfill({ status: 500, json: { error: "Server error" } })
  );
  await page.reload({ waitUntil: "networkidle" });
  if (!(await page.getByText(/error|failed|retry/i).isVisible({ timeout: 3000 })))
    throw new Error("No error state for 500");
  return { message: "API states handled" };
}
```

## Toast / Notification

```ts
import type { Page } from "playwright";
export const URL = "http://localhost:3000";

export async function validate(page: Page) {
  await page.getByRole("button", { name: "Save" }).click();
  const toast = page.locator("[role='alert'], [class*='toast'], [class*='notification']");
  if (!(await toast.first().isVisible({ timeout: 5000 })))
    throw new Error("No toast appeared");
  await page.waitForTimeout(6000);
  if (await toast.first().isVisible().catch(() => false))
    throw new Error("Toast did not auto-dismiss");
  return { message: "Notifications work" };
}
```

## Modal / Dialog

```ts
import type { Page } from "playwright";
export const URL = "http://localhost:3000";

export async function validate(page: Page) {
  await page.getByRole("button", { name: "Open Dialog" }).click();
  const dialog = page.locator("[role='dialog'], [class*='modal']");
  if (!(await dialog.isVisible({ timeout: 3000 }))) throw new Error("Modal did not open");

  await page.keyboard.press("Escape");
  if (await dialog.isVisible({ timeout: 3000 }).catch(() => false))
    throw new Error("Modal did not close on Escape");
  return { message: "Modal behavior correct" };
}
```

## Accessibility Quick Check

```ts
import type { Page } from "playwright";
export const URL = "http://localhost:3000";

export async function validate(page: Page) {
  const issues: string[] = [];

  const noAlt = await page.locator("img:not([alt])").count();
  if (noAlt > 0) issues.push(`${noAlt} images without alt text`);

  const buttons = page.locator("button");
  for (let i = 0; i < await buttons.count(); i++) {
    const btn = buttons.nth(i);
    const name = (await btn.getAttribute("aria-label")) || (await btn.innerText());
    if (!name?.trim()) issues.push(`Button ${i} has no accessible name`);
  }

  const inputs = page.locator("input:not([type='hidden'])");
  for (let i = 0; i < await inputs.count(); i++) {
    const inp = inputs.nth(i);
    const hasLabel =
      (await inp.getAttribute("aria-label")) ||
      (await inp.getAttribute("aria-labelledby")) ||
      ((await inp.getAttribute("id")) &&
        (await page.locator(`label[for='${await inp.getAttribute("id")}']`).count()) > 0);
    if (!hasLabel) issues.push(`Input ${i} has no label`);
  }

  if (issues.length > 0) throw new Error(`A11y issues: ${issues.join("; ")}`);
  return { message: "Basic a11y checks pass" };
}
```
