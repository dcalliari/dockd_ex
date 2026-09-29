import { expect, test } from "@playwright/test";
import { fillEntrar, owner } from "./sign-in";

test("a visitor explores the catalog and each game without an account", async ({ page }) => {
  await page.goto("/");
  await expect(page.locator("#strip-lancamentos .dk-card").filter({ hasText: "Future Beta" })).toBeVisible();
  const navBottom = (await page.locator(".dk-nav").boundingBox())!.y + (await page.locator(".dk-nav").boundingBox())!.height;
  expect((await page.locator("#showcase-lancamentos").boundingBox())!.y).toBeGreaterThanOrEqual(navBottom + 16);
  await expect(page.locator("#library-grid")).toHaveCount(0);
  await expect(page.locator(".dk-bottomnav")).toHaveCount(0);

  await page.locator("#showcase-recentes").getByRole("link", { name: "Ver todos" }).click();
  await expect(page).toHaveURL("http://localhost:4460/descobrir?lista=recentes");
  await expect(page.locator("#discover-list")).toContainText("Chegaram agora");
  const discoverNavBottom = (await page.locator(".dk-nav").boundingBox())!.y + (await page.locator(".dk-nav").boundingBox())!.height;
  expect((await page.locator("#discover-list").boundingBox())!.y).toBeGreaterThanOrEqual(discoverNavBottom + 16);

  const card = page.locator("#discover-results .dk-card").filter({ hasText: "Mystery Quest" });
  await card.locator(".dk-poster").click();
  await expect(page.getByRole("heading", { name: "Mystery Quest" })).toBeVisible();
  await expect(page.locator("#game-sign-in")).toHaveText("+ Adicionar");
  await expect(page.locator("#buy-button")).toHaveCount(0);
  await expect(page.locator(".dk-row__end")).toHaveCount(0);
  await expect(page.locator("#game-history")).toHaveCount(0);

  await page.locator("#game-back").click();
  await expect(page).toHaveURL("http://localhost:4460/descobrir");
});

test("the tag leads to Entrar and back to the same card with its menu open", async ({ page }) => {
  await page.goto("/descobrir?q=Visitor+Pick");
  const card = page.locator("#discover-results .dk-card").filter({ hasText: "Visitor Pick" });
  await card.getByTitle("Entrar para adicionar").click();
  await expect(page).toHaveURL(/\/entrar\?volta=/);

  await fillEntrar(page, owner.password);

  await expect(page).toHaveURL(/\/descobrir\?.*abrir=result-/);
  await expect(page).toHaveURL(/[?&]q=Visitor\+Pick/);
  const menu = card.locator(".dk-status-menu.is-open");
  await expect(menu.locator(".dk-status-menu__options")).toBeVisible();
  await menu.locator("button[phx-value-status=quero]").click();
  await expect(card.locator(".dk-status--quero")).toBeVisible();
  await expect(card.locator(".dk-status-menu.is-open")).toHaveCount(0);
});

test("the game page tag leads to Entrar and back with the control open", async ({ page }) => {
  await page.goto("/descobrir?q=Visitor+Pick");
  await page.locator("#discover-results .dk-card").filter({ hasText: "Visitor Pick" }).locator(".dk-poster").click();
  await page.locator("#game-sign-in").click();
  await expect(page).toHaveURL(/\/entrar\?volta=/);

  await fillEntrar(page, owner.password);

  await expect(page).toHaveURL(/\/jogos\/.*abrir=status/);
  const control = page.locator("#game-status.is-open");
  await expect(control.locator(".dk-status-menu__options")).toBeVisible();
  await control.locator("button.dk-status--jogando").click();
  await page.locator("#game-status button[phx-click=own_elsewhere]").click();
  await expect(page.locator("#game-status .dk-status-menu__current .dk-status--jogando")).toBeVisible();
  await expect(page.locator("#game-status.is-open")).toHaveCount(0);
});
