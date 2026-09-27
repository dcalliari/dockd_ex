import { expect, test } from "@playwright/test";
import { signIn } from "./sign-in";

// One status control everywhere: pointing opens the other statuses, clicking the current tag
// takes the game out, in place. On a touch screen the first tap opens and the second clears.

test("the tag clears the status on the grid and on the game page, in place", async ({ page }) => {
  await signIn(page);
  await expect(page.locator(".dk-card__trash")).toHaveCount(0);

  const card = page.locator("#library-grid .dk-card").filter({ hasText: "Owned Game 5" });
  const menu = card.locator(".dk-status-menu");
  await expect(menu.locator(".dk-status-menu__options")).toBeHidden();
  await menu.locator(".dk-status-menu__current").hover();
  await expect(menu.locator(".dk-status-menu__options")).toBeVisible();
  await expect(menu.locator(".dk-status-menu__options .dk-status--backlog")).toHaveCount(0);

  await menu.locator(".dk-status-menu__current").click();
  await expect(card.locator(".dk-status--add")).toHaveText("+ Adicionar");
  await expect(card).not.toHaveAttribute("data-status");

  // Backlog again asks the version in the same place.
  await menu.locator(".dk-status-menu__current").hover();
  await menu.locator(".dk-status-menu__options .dk-status--backlog").click();
  await expect(menu.locator(".dk-status-menu__ask")).toContainText("Tem em qual versão?");
  await menu.locator(".dk-status-menu__ask button", { hasText: "Switch · Físico" }).click();
  await expect(card).toHaveAttribute("data-status", "backlog");

  await card.locator(".dk-card__text").click();
  await expect(page.getByRole("heading", { name: "Owned Game 5" })).toBeVisible();
  await expect(page.getByText("Tirar da biblioteca", { exact: true })).toHaveCount(0);
  const control = page.locator("#game-status");
  await control.locator(".dk-status-menu__current").hover();
  await expect(control.locator(".dk-status-menu__options")).toBeVisible();
  await control.locator(".dk-status-menu__current").click();
  await expect(control.locator(".dk-status--add")).toBeVisible();
  await expect(page).toHaveURL(/\/jogos\//);
  await expect(page.locator("#game-history .dk-history__item--current")).toContainText("Saiu da biblioteca");
  await expect(page.locator("#buy-button")).toBeVisible();
});

test.describe("on a phone", () => {
  test.use({ viewport: { width: 375, height: 800 }, hasTouch: true, isMobile: true });

  test("first tap opens, second clears, and nothing overflows", async ({ page }) => {
    await signIn(page);
    const card = page.locator("#library-grid .dk-card").filter({ hasText: "Future Veto" });
    const menu = card.locator(".dk-status-menu");

    await menu.locator(".dk-status-menu__current").tap();
    await expect(menu.locator(".dk-status-menu__options")).toBeVisible();
    await expect(card).toHaveAttribute("data-status", "quero");
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBe(375);

    await menu.locator(".dk-status-menu__current").tap();
    await expect(card.locator(".dk-status--add")).toBeVisible();

    await menu.locator(".dk-status-menu__current").tap();
    await menu.locator(".dk-status-menu__options .dk-status--quero").tap();
    await expect(card).toHaveAttribute("data-status", "quero");

    await card.locator(".dk-card__text").tap();
    await expect(page.getByRole("heading", { name: "Future Veto" })).toBeVisible();
    const control = page.locator("#game-status");
    await control.locator(".dk-status-menu__current").tap();
    await expect(control.locator(".dk-status-menu__options")).toBeVisible();
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBe(375);
    const box = await control.locator(".dk-status-menu__options").boundingBox();
    expect(box!.x + box!.width).toBeLessThanOrEqual(375);

    await page.locator("h1").tap();
    await expect(control.locator(".dk-status-menu__options")).toBeHidden();
  });
});
