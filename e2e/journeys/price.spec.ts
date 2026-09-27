import { expect, test } from "@playwright/test";
import { signIn } from "./sign-in";

// Store Quest has an eShop price in priv/repo/e2e_seeds.exs, on sale, and no price of the
// user's: the version shows the store's price without anyone typing it.
test("the eShop price shows on the game page without typing it", async ({ page }) => {
  await signIn(page);
  await page.goto("/descobrir?q=Store+Quest");

  const card = page.locator("#discover-results .dk-card").filter({ hasText: "Store Quest" });
  await card.locator(".dk-poster").click();
  await expect(page.getByRole("heading", { name: "Store Quest" })).toBeVisible();

  const price = page.locator("[id^=release-] .dk-price");
  await expect(price).toContainText("R$ 99,90");
  await expect(price).toContainText("eShop");
});
