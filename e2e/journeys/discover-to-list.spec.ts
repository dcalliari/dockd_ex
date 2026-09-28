import { expect, test } from "@playwright/test";
import { signIn } from "./sign-in";

test("a new game goes from Descobrir to the Biblioteca as Quero and can be started", async ({ page }) => {
  await signIn(page);
  await page.goto("/descobrir");
  await page.locator("#nav-search").fill("Discovery Candidate");
  const results = page.getByTestId("discover-results").or(page.locator("#discover-results"));
  const candidate = results.locator(".dk-card").filter({ hasText: "Discovery Candidate" });
  await expect(candidate).toBeVisible();
  await candidate.locator(".dk-status-menu__current").hover();
  await candidate.locator("button[phx-value-status=quero]").click();
  await expect(candidate.locator(".dk-status--quero")).toBeVisible();

  await page.goto("/biblioteca?tab=quero");
  const card = page.locator("#library-grid .dk-card").filter({ hasText: "Discovery Candidate" });
  await expect(card).toBeVisible();
  await expect(card.locator(".dk-status--quero")).toBeVisible();

  await card.locator(".dk-card__text").click();
  await expect(page.getByRole("heading", { name: "Discovery Candidate" })).toBeVisible();
  await expect(page.locator("#buy-button")).toBeVisible();

  await page.locator("#game-status .dk-status-menu__current").hover();
  await page.locator("#game-status button.dk-status--jogando").click();
  await expect(page.locator("#game-history")).toContainText("Começou a jogar");

  await page.locator("#game-back").click();
  await expect(page).toHaveURL("http://localhost:4460/biblioteca");
  await expect(page.locator("#library-grid .dk-card").filter({ hasText: "Discovery Candidate" }).locator(".dk-status--jogando")).toBeVisible();
});
