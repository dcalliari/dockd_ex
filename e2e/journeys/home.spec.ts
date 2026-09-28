import { expect, test } from "@playwright/test";
import { signIn } from "./sign-in";

const shots = process.env.DOCKD_SHOTS_DIR;

for (const scheme of ["light", "dark"] as const) {
  test.describe(`${scheme}`, () => {
    test.use({ colorScheme: scheme });

    test(`the account home keeps the wishlist rail at 1280 (${scheme})`, async ({ page }) => {
      await page.setViewportSize({ width: 1280, height: 800 });
      await signIn(page);
      await expect(page.locator("#home-upcoming")).toBeVisible();
      await expect(page.locator("#home-upcoming-strip .dk-card")).toHaveCount(3);
      await expect(page.locator(".dk-nav__link[href='/biblioteca']")).toBeVisible();
      if (shots) await page.screenshot({ path: `${shots}/inicio-1280-${scheme}.png` });
    });
  });

  test.describe(`${scheme} on a phone`, () => {
    test.use({ colorScheme: scheme, viewport: { width: 375, height: 800 }, hasTouch: true, isMobile: true });

    test(`the account home fits at 375 (${scheme})`, async ({ page }) => {
      await signIn(page);
      await expect(page.locator("#home-upcoming")).toBeVisible();
      expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBe(375);
      if (shots) await page.screenshot({ path: `${shots}/inicio-375-${scheme}.png` });
    });
  });
}
