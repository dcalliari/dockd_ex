import { expect, type Page } from "@playwright/test";

// Account created by priv/repo/e2e_seeds.exs.
export const owner = { email: "e2e@dockd.local", password: "senha-da-jornada-e2e" };

export async function signIn(page: Page) {
  await page.goto("/entrar");
  await page.getByPlaceholder("E-mail").fill(owner.email);
  await page.getByPlaceholder("Senha").fill(owner.password);
  await page.locator("#entrar-submit").click();
  await expect(page.locator("#account-menu")).toBeVisible();
}
