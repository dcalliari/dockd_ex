import { expect, test } from "@playwright/test";
import { signIn } from "./sign-in";

// Editions are versions of the same game (design/maquetes/edicoes.html): Edition Quest is
// sold as the standard edition and three others (priv/repo/e2e_seeds.exs). Versões shows
// the two cheapest under Switch and opens the rest in place; Comprei opens every choice
// with its price under the hero, and the one chosen is the purchase. Nothing here may
// open a native browser dialog.

test.beforeEach(async ({ page }) => {
  page.on("dialog", (dialog) => {
    throw new Error(`native dialog: ${dialog.message()}`);
  });
});

async function openGame(page) {
  await signIn(page);
  await page.goto("/descobrir?q=Edition%20Quest");
  await page.locator(".dk-card", { hasText: "Edition Quest" }).locator("a").first().click();
  await expect(page.getByRole("heading", { name: "Edition Quest" })).toBeVisible();
}

test("Versões shows the editions under their platform and opens the rest in place", async ({
  page,
}) => {
  await openGame(page);

  const editions = page.locator(".dk-editions");
  await expect(editions.locator(".dk-edition")).toHaveCount(2);
  await expect(editions).toContainText("Deluxe Edition");
  await expect(editions).toContainText("R$ 249,90");
  await expect(editions).not.toContainText("Ultimate Edition");

  await editions.getByRole("button", { name: "Mais 1 edição" }).click();
  await expect(editions.locator(".dk-edition")).toHaveCount(3);
  await editions.getByRole("button", { name: "Menos edições" }).click();
  await expect(editions.locator(".dk-edition")).toHaveCount(2);
});

test("Comprei opens the choices with their prices and buys the one chosen", async ({ page }) => {
  await openGame(page);

  await page.locator("#buy-button").click();
  const options = page.locator("#buy-options");
  // The standard edition first, physical and digital, then the two cheapest editions.
  const standard = options.locator(".dk-buy__option", { hasText: "Edição padrão" });
  await expect(standard).toHaveCount(2);
  await expect(standard.filter({ hasText: "Digital" })).toContainText("R$ 199,90");
  await expect(options.locator(".dk-buy__option")).toHaveCount(4);

  await options.getByRole("button", { name: "Mais 1 edição" }).click();
  await expect(options.locator(".dk-buy__option")).toHaveCount(5);

  await options
    .locator(".dk-buy__option", { hasText: "Gold Edition" })
    .getByRole("button", { name: "Comprei esta" })
    .click();

  await expect(options).toHaveCount(0);
  await expect(page.locator("#buy .dk-price--paid")).toContainText("R$ 299,90");
  const gold = page.locator(".dk-edition", { hasText: "Gold Edition" });
  await expect(gold.locator(".dk-row__meta")).toContainText("Tem");

  await page.locator("#buy").getByRole("button", { name: "Desfazer" }).click();
  await expect(page.locator("#buy-button")).toBeVisible();
});

test.describe("on a phone", () => {
  test.use({ viewport: { width: 375, height: 800 }, hasTouch: true, isMobile: true });

  test("the editions and the choices fit the screen", async ({ page }) => {
    await openGame(page);
    await expect(page.locator(".dk-edition").first()).toBeVisible();
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBe(375);

    await page.locator("#buy-button").click();
    await expect(page.locator(".dk-buy__option").first()).toBeVisible();
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBe(375);
  });
});
