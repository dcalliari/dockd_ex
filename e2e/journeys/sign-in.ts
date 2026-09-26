import { expect, type Page } from "@playwright/test";

// Account created by priv/repo/e2e_seeds.exs.
export const owner = { email: "e2e@dockd.local", password: "senha-da-jornada-e2e" };

// Entrar focuses the email field when LiveView connects; typing before that can land in
// the wrong field.
export async function connected(page: Page) {
  await expect(page.locator("[data-phx-main].phx-connected")).toHaveCount(1);
}

export async function fillEntrar(page: Page, password: string) {
  await connected(page);
  await page.getByPlaceholder("E-mail").fill(owner.email);
  await page.getByPlaceholder("Senha").fill(password);
  await page.locator("#entrar-submit").click();
}

export async function signIn(page: Page) {
  await page.goto("/entrar");
  await fillEntrar(page, owner.password);
  await expect(page.locator("#account-menu")).toBeVisible();
}
