import { expect, test } from "@playwright/test";
import { signIn } from "./sign-in";

// Conferir catálogo (design/maquetes/edicoes.html): Calamity Warriors and its Definitive
// Edition wait in Mesmo jogo?, and Review Quest waits in Na eShop with two candidates
// (priv/repo/e2e_seeds.exs, design/maquetes/casar-eshop.html, caminho A). Every answer and
// its Desfazer happen in the row itself; nothing here may open a native browser dialog.

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
  await expect(page.locator("#account-catalog-review small")).toHaveText("2");
  await page.locator("#account-catalog-review").click();
  await expect(page).toHaveURL("http://localhost:4460/conferir");

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

test("Mesmo jogo? joins the two games and Desfazer puts them apart, in place", async ({
  page,
}) => {
  await signIn(page);
  await page.goto("/conferir");

  const head = page.locator("#same-game-head");
  const row = page.locator(".dk-same").filter({ hasText: "Calamity Warriors" });
  const meta = row.locator(":scope > .dk-row .dk-row__meta");
  await expect(head).toContainText("1");
  await expect(row.locator(".dk-same__candidate")).toContainText("Definitive Edition");
  await expect(row.locator(".dk-same__candidate")).toContainText("expandido");

  await row.getByRole("button", { name: "É o mesmo jogo" }).click();
  await expect(meta).toContainText("mesmo jogo");
  await expect(row.locator(".dk-same__candidate")).toHaveCount(0);
  await expect(head).toContainText("0");

  await row.getByRole("button", { name: "Desfazer" }).click();
  await expect(row.locator(".dk-same__candidate")).toContainText("Definitive Edition");
  await expect(meta).toContainText("mesmo jogo?");

  await row.getByRole("button", { name: "É outro jogo" }).click();
  await expect(meta).toContainText("jogos diferentes");
  await row.getByRole("button", { name: "Desfazer" }).click();
  await expect(head).toContainText("1");
});

test("the old address still opens the queue", async ({ page }) => {
  await signIn(page);
  await page.goto("/eshop");
  await expect(page.locator("#same-game-head")).toBeVisible();
});

test.describe("on a phone", () => {
  test.use({ viewport: { width: 375, height: 800 }, hasTouch: true, isMobile: true });

  test("the questions fit the screen", async ({ page }) => {
    await signIn(page);
    await page.goto("/conferir");

    await expect(page.locator(".dk-same__candidate").first()).toBeVisible();
    await expect(page.locator(".dk-match__option").first()).toBeVisible();
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBe(375);
  });
});
