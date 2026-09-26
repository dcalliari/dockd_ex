import { expect, test } from "@playwright/test";
import { owner, signIn } from "./sign-in";

test("a visitor signs in with the right password and out again", async ({ page }) => {
  await page.goto("/comprar");
  await expect(page).toHaveURL("http://localhost:4460/entrar");
  await expect(page.locator(".dk-nav__links")).toHaveCount(0);

  await page.getByPlaceholder("E-mail").fill(owner.email);
  await page.getByPlaceholder("Senha").fill("senha errada de novo");
  await page.locator("#entrar-submit").click();
  await expect(page.locator(".dk-field.is-error .dk-field__error")).toHaveText("E-mail ou senha errados");

  await page.getByPlaceholder("Senha").fill(owner.password);
  await page.locator("#entrar-submit").click();
  await expect(page).toHaveURL("http://localhost:4460/comprar");

  await page.locator("#account-menu summary").click();
  await expect(page.locator("#account-menu .dk-account__who")).toHaveText(owner.email);
  await page.locator("#account-sign-out").click();
  await expect(page).toHaveURL("http://localhost:4460/entrar");
  await page.goto("/");
  await expect(page).toHaveURL("http://localhost:4460/entrar");
});

test("a new account starts with an empty library of its own", async ({ page }) => {
  await page.goto("/entrar");
  await page.locator("#entrar-register").click();
  await expect(page.locator("#entrar-submit")).toHaveText("Criar conta");

  await page.getByPlaceholder("E-mail").fill(`nova-${Date.now()}@dockd.local`);
  await page.getByPlaceholder("Senha").fill("uma senha bem longa");
  await page.locator("#entrar-submit").click();

  await expect(page).toHaveURL("http://localhost:4460/");
  await expect(page.locator("#library-grid .dk-card")).toHaveCount(0);
  await expect(page.locator("#account-menu summary")).toContainText("Nova");
});

test("the owner's library is still there after signing in", async ({ page }) => {
  await signIn(page);
  await expect(page.locator("#library-grid .dk-card").filter({ hasText: "Owned Adventure" })).toBeVisible();
});
