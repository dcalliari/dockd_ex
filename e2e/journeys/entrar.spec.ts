import { expect, test } from "@playwright/test";
import { baseURL } from "../base-url";
import { connected, fillEntrar, owner, signIn } from "./sign-in";

test("a visitor signs in with the right password and out again", async ({ page }) => {
  await page.goto("/comprar");
  await expect(page).toHaveURL(`${baseURL}/entrar`);
  await expect(page.locator(".dk-nav__guest a[aria-current=page]")).toHaveText("Entrar");
  await expect(page.locator("#entrar-wall .dk-poster").first()).toBeVisible();
  await expect(page.locator(".dk-auth-panel #entrar-form")).toBeVisible();

  await fillEntrar(page, "senha errada de novo");
  await expect(page.locator(".dk-field.is-error .dk-field__error")).toHaveText("E-mail ou senha errados");

  await page.getByPlaceholder("Senha").fill(owner.password);
  await page.locator("#entrar-submit").click();
  await expect(page).toHaveURL(`${baseURL}/comprar`);

  await page.locator("#account-menu summary").click();
  await expect(page.locator("#account-menu .dk-account__who")).toHaveText(owner.email);
  await page.locator("#account-sign-out").click();
  await expect(page).toHaveURL(`${baseURL}/`);
  await expect(page.locator("#strip-lancamentos")).toBeVisible();
  await expect(page.locator("#account-menu")).toHaveCount(0);
});

test("a new account starts with an empty library of its own", async ({ page }) => {
  await page.goto("/");
  await page.locator(".dk-nav__guest a", { hasText: "Criar conta" }).click();
  await expect(page).toHaveURL(`${baseURL}/criar-conta`);
  await expect(page.locator("#entrar-submit")).toHaveText("Criar conta");
  await connected(page);

  await page.getByPlaceholder("E-mail").fill(`nova-${Date.now()}@dockd.local`);
  await page.getByPlaceholder("Senha").fill("uma senha bem longa");
  await page.locator("#entrar-submit").click();

  await expect(page).toHaveURL(`${baseURL}/`);
  await expect(page.locator("#library-grid")).toHaveCount(0);
  await expect(page.locator("#account-menu summary")).toContainText("Nova");
});

test("the owner's library is still there after signing in", async ({ page }) => {
  await signIn(page);
  await page.goto("/biblioteca");
  await expect(page.locator("#library-grid .dk-card").filter({ hasText: "Owned Adventure" })).toBeVisible();
});
