import { test, expect } from "@playwright/test";

const base = process.env.E2E_BASE_URL;

test.skip(!base, "E2E_BASE_URL is not set");

test("home responds quickly", async ({ page }) => {
  const start = Date.now();
  await page.goto("/", { waitUntil: "domcontentloaded" });
  const ttfbMs = Date.now() - start;
  expect(page.url()).toContain("/");
  expect(ttfbMs).toBeLessThan(1000); // budget for client TTI < 1s
});

test("reconciliation route loads", async ({ page }) => {
  await page.goto("/reconciliation", { waitUntil: "domcontentloaded" });
  await expect(page.locator("text=Reconciliation")).toBeVisible();
});


