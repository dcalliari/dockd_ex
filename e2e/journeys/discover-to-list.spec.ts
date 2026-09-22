import { expect, test } from "@playwright/test";

test("a new game moves from Discover to List and can be removed", async ({ page }) => {
  await page.goto("/catalogo");
  await expect(page.getByRole("heading", { name: "Descobrir" })).toBeVisible();
  await page.getByLabel("Buscar").fill("Discovery Candidate");
  const result = page.getByTestId("discover-results");
  await expect(result).toContainText("Discovery Candidate");
  await result.getByRole("button", { name: "Quero jogar" }).click();
  await expect(result).toContainText("Na lista");

  await page.goto("/");
  await expect(page.getByRole("heading", { name: "Lista" })).toBeVisible();
  const listItem = page.getByTestId("list-items").getByText("Discovery Candidate");
  await expect(listItem).toBeVisible();
  await expect(page.getByText("Na lista", { exact: true })).toBeVisible();

  await listItem.click();
  await expect(page.getByRole("heading", { name: "Discovery Candidate" })).toBeVisible();
  await page.getByRole("link", { name: "Lista" }).click();
  await expect(page).toHaveURL("http://localhost:4460/");

  await page.getByTestId("list-items").getByRole("button", { name: /Tirar da lista/i }).click();
  await expect(page.getByTestId("list-items")).not.toContainText("Discovery Candidate");
});
