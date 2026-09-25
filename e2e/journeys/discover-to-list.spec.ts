import { expect, test } from "@playwright/test";

test("a new game goes from Descobrir to the Biblioteca as Quero and can be started", async ({ page }) => {
  await page.goto("/descobrir");
  await page.locator("#nav-search").fill("Discovery Candidate");
  const results = page.getByTestId("discover-results").or(page.locator("#discover-results"));
  const candidate = results.locator(".dk-card").filter({ hasText: "Discovery Candidate" });
  await expect(candidate).toBeVisible();
  await candidate.locator("summary").click();
  await candidate.locator("button[phx-value-status=quero]").click();
  await expect(candidate.locator(".dk-status--quero")).toBeVisible();

  await page.goto("/?tab=quero");
  const card = page.locator("#library-grid .dk-card").filter({ hasText: "Discovery Candidate" });
  await expect(card).toBeVisible();
  await expect(card.locator(".dk-status--quero")).toBeVisible();

  await card.locator(".dk-card__text").click();
  await expect(page.getByRole("heading", { name: "Discovery Candidate" })).toBeVisible();
  await expect(page.locator("#buy-button")).toBeVisible();

  await page.locator("button.dk-status--jogando[phx-click=set_status]").click({ force: true });
  await expect(page.locator("#game-history")).toContainText("Começou a jogar");

  await page.locator("#game-back").click();
  await expect(page).toHaveURL("http://localhost:4460/");
  await expect(page.locator("#library-grid .dk-card").filter({ hasText: "Discovery Candidate" }).locator(".dk-status--jogando")).toBeVisible();
});
