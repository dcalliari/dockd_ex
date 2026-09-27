import { expect, test } from "@playwright/test";
import { signIn } from "./sign-in";

// One line at the end of every screen but Entrar: wordmark, Sobre and the IGDB credit.
// On a phone it ends above the bottom navigation, never under it.

const shots = process.env.DOCKD_SHOTS_DIR;

test("the footer leads to Sobre and stays off the Entrar covers", async ({ page }) => {
  await page.goto("/");
  const footer = page.locator("#site-footer");
  await expect(footer).toContainText("Dados de jogos por IGDB");
  await footer.locator("#footer-about").click();
  await expect(page).toHaveURL(/\/sobre$/);
  await expect(page.getByText("Dados de jogos por IGDB")).toHaveCount(1);

  await page.goto("/entrar");
  await expect(page.locator("#entrar-backdrop")).toBeVisible();
  await expect(page.locator("#site-footer")).toHaveCount(0);
});

for (const scheme of ["light", "dark"] as const) {
  test.describe(`${scheme}`, () => {
    test.use({ colorScheme: scheme });

    test(`at 1280 the footer is one line under a rule (${scheme})`, async ({ page }) => {
      await page.setViewportSize({ width: 1280, height: 800 });
      await signIn(page);
      const line = page.locator("#site-footer .dk-footer__line");
      await page.evaluate(() => window.scrollTo(0, document.documentElement.scrollHeight));
      const box = (await line.boundingBox())!;
      expect(box.height).toBeLessThanOrEqual(40);
      if (shots) await page.screenshot({ path: `${shots}/rodape-1280-${scheme}.png` });
      await page.locator("#footer-about").click();
      await expect(page.locator("#about")).toBeVisible();
      if (shots) await page.screenshot({ path: `${shots}/sobre-1280-${scheme}.png` });
    });
  });

  test.describe(`${scheme} on a phone`, () => {
    test.use({ colorScheme: scheme, viewport: { width: 375, height: 800 }, hasTouch: true, isMobile: true });

    test(`at 375 the footer ends above the bottom navigation (${scheme})`, async ({ page }) => {
      await signIn(page);
      await page.evaluate(() => window.scrollTo(0, document.documentElement.scrollHeight));
      const line = (await page.locator("#site-footer .dk-footer__line").boundingBox())!;
      const nav = (await page.locator(".dk-bottomnav").boundingBox())!;
      expect(line.y + line.height).toBeLessThanOrEqual(nav.y);
      expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBe(375);
      if (shots) await page.screenshot({ path: `${shots}/rodape-375-${scheme}.png` });
    });
  });
}
