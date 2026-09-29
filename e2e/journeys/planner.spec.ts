import { expect, test } from "@playwright/test";
import { connected, signIn } from "./sign-in";

// Planning the queue by media (design/maquetes/planejador.html, caminho A): Sale Quest,
// in Quero and on sale in priv/repo/e2e_seeds.exs, opens Comprar in Promoções; the media
// tag swaps Digital and Físico in one tap, and Agora sums the digital games to buy now.
// Every change is undone at the end so the other journeys see the seeded queue.

const shots = process.env.DOCKD_SHOTS_DIR;

test.beforeEach(async ({ page }) => {
  page.on("dialog", (dialog) => {
    throw new Error(`native dialog: ${dialog.message()}`);
  });
});

test("media, Agora and the totals by media change in place", async ({ page }) => {
  await signIn(page);
  await page.goto("/comprar");
  await connected(page);

  const sale = page.locator("[id^=queue-]").filter({ hasText: "Sale Quest" });
  const expensive = page.locator("[id^=queue-]").filter({ hasText: "Expensive Quest" });
  await expect(page.locator("div[id^=queue-]").first()).toContainText("Sale Quest");
  await expect(sale.locator(".dk-price s")).toContainText("R$ 159,90");
  await expect(sale.locator(".dk-price b")).toContainText("R$ 79,95");
  await expect(page.locator("#planned-total")).toHaveCount(0);

  await sale.getByRole("button", { name: "Agora" }).click();
  await expensive.getByRole("button", { name: "Agora" }).click();
  await expect(page.locator("#planned-total")).toContainText("R$ 379,95");
  await expect(sale.getByRole("button", { name: "Agora" })).toHaveAttribute("aria-pressed", "true");

  await expensive.locator("button.dk-media", { hasText: "Digital" }).click();
  await expect(expensive.locator("button.dk-media")).toHaveText("Físico");
  await expect(expensive.getByRole("button", { name: "Agora" })).toHaveCount(0);
  await expect(page.locator("#planned-total")).toContainText("R$ 79,95");
  await expect(page.locator("#estimate-digital")).toContainText("R$ 179,95");
  await expect(page.locator("#estimate-physical")).toContainText("Sem preço");
  await expect(page.locator("#estimate-physical")).toContainText("1 jogo");

  // Still Quero after a reload: Agora is a plan, not a status.
  await page.reload();
  await connected(page);
  await expect(page.locator("#planned-total")).toContainText("R$ 79,95");
  await expect(sale.locator(".dk-status--backlog")).toHaveCount(0);

  // Back to Digital it is not marked: Agora is only for digital games.
  await expensive.locator("button.dk-media", { hasText: "Físico" }).click();
  await expect(page.locator("#estimate-physical")).toHaveCount(0);
  await expect(expensive.getByRole("button", { name: "Agora" })).toHaveAttribute("aria-pressed", "false");
  await expect(page.locator("#planned-total")).toContainText("R$ 79,95");

  await sale.getByRole("button", { name: "Agora" }).click();
  await expect(page.locator("#planned-total")).toHaveCount(0);
});

for (const scheme of ["light", "dark"] as const) {
  test.describe(`${scheme}`, () => {
    test.use({ colorScheme: scheme });

    test(`Comprar at 1280 with a game marked Agora (${scheme})`, async ({ page }) => {
      await page.setViewportSize({ width: 1280, height: 900 });
      await signIn(page);
      await page.goto("/comprar");
      await connected(page);
      const sale = page.locator("[id^=queue-]").filter({ hasText: "Sale Quest" });
      await sale.getByRole("button", { name: "Agora" }).click();
      await expect(page.locator("#planned-total")).toContainText("R$ 79,95");
      if (shots) await page.screenshot({ path: `${shots}/comprar-1280-${scheme}.png`, fullPage: true, animations: "disabled" });
      await sale.getByRole("button", { name: "Agora" }).click();
      await expect(page.locator("#planned-total")).toHaveCount(0);
    });
  });

  test.describe(`${scheme} on a phone`, () => {
    test.use({ colorScheme: scheme, viewport: { width: 375, height: 800 }, hasTouch: true, isMobile: true });

    test(`Comprar fits at 375 with media and Agora (${scheme})`, async ({ page }) => {
      await signIn(page);
      await page.goto("/comprar");
      await connected(page);
      const sale = page.locator("[id^=queue-]").filter({ hasText: "Sale Quest" });
      await sale.getByRole("button", { name: "Agora" }).tap();
      await expect(page.locator("#planned-total")).toContainText("R$ 79,95");
      expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBe(375);
      if (shots) await page.screenshot({ path: `${shots}/comprar-375-${scheme}.png`, fullPage: true, animations: "disabled" });
      await sale.getByRole("button", { name: "Agora" }).tap();
      await expect(page.locator("#planned-total")).toHaveCount(0);
    });
  });
}
