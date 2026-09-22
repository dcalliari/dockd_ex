import { expect, test } from "@playwright/test";

test("a new game moves from Discover to List and can be removed", async ({ page }) => {
  await page.goto("/catalogo");
  await expect(page.getByRole("heading", { name: "Descobrir" })).toBeVisible();
  await page.getByLabel("Buscar").fill("Discovery Candidate");
  const result = page.getByTestId("discover-results");
  const candidate = result.getByRole("article").filter({ hasText: "Discovery Candidate" });
  await expect(candidate).toBeVisible();
  await candidate.getByRole("button", { name: "Quero jogar" }).click();
  await expect(candidate).toContainText("Na lista");

  await page.goto("/");
  await expect(page.getByRole("heading", { name: "Lista" })).toBeVisible();
  const listEntry = page
    .getByTestId("list-items")
    .getByRole("article")
    .filter({ hasText: "Discovery Candidate" });
  await expect(listEntry).toBeVisible();
  await expect(listEntry.getByText("Na lista", { exact: true })).toBeVisible();

  await listEntry.getByRole("link", { name: "Discovery Candidate" }).click();
  await expect(page.getByRole("heading", { name: "Discovery Candidate" })).toBeVisible();
  await page.locator("#game-back").click();
  await expect(page).toHaveURL("http://localhost:4460/");

  const listEntryAfterReturn = page
    .getByTestId("list-items")
    .getByRole("article")
    .filter({ hasText: "Discovery Candidate" });
  await listEntryAfterReturn.getByRole("button", { name: "Tirar" }).click();
  await expect(page.getByTestId("list-items")).not.toContainText("Discovery Candidate");
});
