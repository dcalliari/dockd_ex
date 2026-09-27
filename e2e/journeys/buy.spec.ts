import { expect, test } from "@playwright/test";
import { signIn } from "./sign-in";

// Comprei in the place of the button (design/maquetes/compra.html, caminho A): the queue
// line shows the estimated total per media, Comprei asks the media when there are two,
// the answer is the purchase at the price seen, and Desfazer brings the game back. Nothing
// here may open a native browser dialog.

test.beforeEach(async ({ page }) => {
  page.on("dialog", (dialog) => {
    throw new Error(`native dialog: ${dialog.message()}`);
  });
});

test("Comprei buys at the price seen and Desfazer undoes it, in place", async ({ page }) => {
  await signIn(page);
  await page.goto("/comprar");

  await expect(page.locator("#estimate-digital")).toContainText("R$ 400,00");
  await expect(page.locator("#estimate-digital")).toContainText("em 2 de 6");
  await expect(page.locator("#estimate-physical")).toHaveCount(0);

  const row = page.locator("[id^=queue-]").filter({ hasText: "Buyable Quest" });
  await row.getByRole("button", { name: "Comprei" }).click();
  await row.locator(".dk-choice button", { hasText: "Digital" }).click();

  await expect(row.locator(".dk-status--backlog")).toBeVisible();
  await expect(row.locator(".dk-price--paid")).toContainText("R$ 100,00");
  await expect(page.locator("#estimate-digital")).toContainText("em 1 de 5");
  await expect(page.locator("#month-spending")).toContainText("R$ 100,00");

  await row.getByRole("button", { name: "Desfazer" }).click();
  await expect(row.getByRole("button", { name: "Comprei" })).toBeVisible();
  await expect(page.locator("#month-spending")).toHaveCount(0);
  await expect(page.locator("#estimate-digital")).toContainText("em 2 de 6");
});

test("the price opens the manual record under the row and keeps it", async ({ page }) => {
  await signIn(page);
  await page.goto("/comprar");

  const row = page.locator("[id^=queue-]").filter({ hasText: "Mystery Quest" });
  await row.locator("button.dk-price", { hasText: "Sem preço" }).click();
  const form = row.locator("form.dk-form");
  await form.locator(".dk-choice label", { hasText: "Físico" }).click();
  await form.getByLabel("Preço visto").fill("249,90");
  await form.getByLabel("Onde viu").fill("Amazon");
  await form.getByRole("button", { name: "Registrar preço" }).click();

  await expect(row.locator("button.dk-price")).toContainText("R$ 249,90");
  await expect(page.locator("#estimate-physical")).toContainText("em 1 de 6");
});

test.describe("on a phone", () => {
  test.use({ viewport: { width: 375, height: 800 }, hasTouch: true, isMobile: true });

  test("the version question fits in the row", async ({ page }) => {
    await signIn(page);
    await page.goto("/comprar");

    const row = page.locator("[id^=queue-]").filter({ hasText: "Expensive Quest" });
    await row.getByRole("button", { name: "Comprei" }).tap();
    await expect(row.locator(".dk-choice button", { hasText: "Físico" })).toBeVisible();
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBe(375);
    await row.getByRole("button", { name: "Cancelar" }).tap();
    await expect(row.getByRole("button", { name: "Comprei" })).toBeVisible();
  });
});
