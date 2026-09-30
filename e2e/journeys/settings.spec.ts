import { expect, test } from "@playwright/test";
import { signIn } from "./sign-in";

test("account settings update in place and keep destructive confirmation in the app", async ({ page }) => {
  await signIn(page);
  await page.locator("#account-menu summary").click();
  await page.locator("#account-settings").click();

  await expect(page).toHaveURL(/\/configuracoes$/);
  await expect(page.locator("#settings-profile-link")).toBeVisible();
  await expect(page.locator("#settings-profile-form")).toBeVisible();

  await page.locator("#settings-profile-submit").click();
  await expect(page.locator("#settings-profile-notice")).toHaveText("Perfil atualizado");

  await page.locator("#settings-edit-password").click();
  await page.locator("#password_current_password").fill("senha errada de novo");
  await page.locator("#password_new_password").fill("uma senha bem longa");
  await page.locator("#password_confirmation").fill("uma senha bem longa");
  await page.locator("#settings-password-submit").click();
  await expect(page.locator("#settings-password-form .dk-field__error")).toHaveText(
    "Senha atual incorreta"
  );

  await expect(page.locator("#settings-export")).toHaveAttribute("href", "/configuracoes/exportar");
  await page.locator("#settings-delete").click();
  await expect(page.locator("#settings-delete-modal[role=\"presentation\"]")).toBeVisible();
  await page.locator("#delete_confirmation").fill("apagar");
  await page.locator("#settings-delete-submit").click();
  await expect(page.locator("#settings-delete-form .dk-field__error")).toHaveText(
    "Digite EXCLUIR para continuar"
  );
  await page.locator("#settings-delete-cancel").click();
  await expect(page.locator("#settings-delete-modal")).toHaveCount(0);
});

test.describe("on a phone", () => {
  test.use({ viewport: { width: 375, height: 800 }, hasTouch: true, isMobile: true });

  test("settings fit at 375", async ({ page }) => {
    await signIn(page);
    await page.goto("/configuracoes");

    await expect(page.locator("#settings-sections")).toBeVisible();
    await expect(page.locator("#settings-profile-form")).toBeVisible();
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBe(375);
  });
});
