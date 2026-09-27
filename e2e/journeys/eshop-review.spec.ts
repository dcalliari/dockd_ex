import { expect, test } from "@playwright/test";
import { signIn } from "./sign-in";

// Escolher na eShop (design/maquetes/casar-eshop.html, caminho A): Review Quest waits in
// priv/repo/e2e_seeds.exs with two candidates. Choosing, rejecting and undoing happen in
// the row itself; nothing here may open a native browser dialog.

test.beforeEach(async ({ page }) => {
  page.on("dialog", (dialog) => {
    throw new Error(`native dialog: ${dialog.message()}`);
  });
});

test("the account menu leads to the queue, where a choice prices the version in place", async ({
  page,
}) => {
  await signIn(page);
  await page.locator("#account-menu summary").click();
  await page.locator("#account-eshop-review").click();
  await expect(page).toHaveURL("http://localhost:4460/eshop");

  const row = page.locator(".dk-match").filter({ hasText: "Review Quest" }).first();
  const version = row.locator(":scope > .dk-row .dk-row__meta");
  await expect(row.locator(".dk-match__option")).toHaveCount(2);
  await expect(row.locator(".dk-match__option").first()).toContainText("R$ 46,99");

  await row.locator(".dk-match__option").first().getByRole("button", { name: "É este" }).click();
  await expect(row.locator(".dk-match__option")).toHaveCount(0);
  await expect(version).toContainText("Director's Edition");
  await expect(row.locator(".dk-price")).toContainText("R$ 46,99");

  await row.getByRole("button", { name: "Desfazer" }).click();
  await expect(row.locator(".dk-match__option")).toHaveCount(2);

  await row.getByRole("button", { name: "Não está na eShop" }).click();
  await expect(version).toContainText("fora da eShop");
  await row.getByRole("button", { name: "Desfazer" }).click();
  await expect(row.locator(".dk-match__option")).toHaveCount(2);
  await expect(version).toContainText("2 candidatos");
});

test.describe("on a phone", () => {
  test.use({ viewport: { width: 375, height: 800 }, hasTouch: true, isMobile: true });

  test("the candidates fit the screen", async ({ page }) => {
    await signIn(page);
    await page.goto("/eshop");

    await expect(page.locator(".dk-match__option").first()).toBeVisible();
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBe(375);
  });
});
