import { expect, test } from "@playwright/test";
import { signIn } from "./sign-in";

const shots = process.env.DOCKD_SHOTS_DIR;

// Perfil e amigos (design/maquetes/perfil-social.html): the profile lives at /u/:username and is
// reached from the account menu; friends are two accounts that follow each other, marked by the
// Amigo label; Seguindo unfollows in place; Só amigos closes the profile to everyone else.

test("Início shows what friends play and the menu leads to the profile", async ({ page }) => {
  await signIn(page);

  const friends = page.locator("#home-friends-strip .dk-card").filter({ hasText: "Friendly Voyage" });
  await expect(page.locator("#home-friends")).toContainText("Amigos jogando");
  await expect(friends.locator(".dk-card__meta")).toHaveText("Amiga");

  await page.locator("#account-menu summary").click();
  await page.locator("#account-profile").click();
  await expect(page).toHaveURL(/\/u\/e2e$/);
  await expect(page.locator("#profile-head h1")).toHaveText("E2e");
  await expect(page.locator("#profile-visibility")).toBeVisible();
  await expect(page.locator("#follow-button")).toHaveCount(0);
  await expect(page.locator("#profile-zerado-strip .dk-card")).toHaveCount(1);
  await expect(page.locator("#profile-quero")).toBeVisible();
  await expect(page.getByText("R$")).toHaveCount(0);
  if (shots) await page.screenshot({ path: `${shots}/perfil-1280.png`, fullPage: true });
});

test("followers show the friend, and following back makes a friend", async ({ page }) => {
  await signIn(page);
  await page.goto("/u/e2e/seguidores");

  await expect(page.locator("#person-amiga .dk-friend")).toHaveText("Amigo");
  await expect(page.locator("#person-amiga .dk-row__meta")).toContainText("Jogando Friendly Voyage");

  const back = page.locator("#follow-fa");
  await expect(back).toHaveText("Seguir de volta");
  await back.click();
  await expect(back).toContainText("Seguindo");
  await expect(page.locator("#person-fa .dk-friend")).toHaveText("Amigo");

  // Pointing at Seguindo says what the click does.
  await back.hover();
  const leave = await back.evaluate((el) => getComputedStyle(el, "::after").content);
  expect(leave).toBe('"Deixar de seguir"');
  await back.click();
  await expect(back).toHaveText("Seguir de volta");
  await expect(page.locator("#person-fa .dk-friend")).toHaveCount(0);
});

test("a friend's profile carries the label and Seguindo", async ({ page }) => {
  await signIn(page);
  await page.goto("/u/amiga");

  await expect(page.locator("#profile-head .dk-friend")).toHaveText("Amigo");
  await expect(page.locator("#follow-button")).toContainText("Seguindo");
  const card = page.locator("#profile-jogando-strip .dk-card").filter({ hasText: "Friendly Voyage" });
  await expect(card.locator(".dk-status--add")).toBeVisible();
  if (shots) await page.screenshot({ path: `${shots}/perfil-amiga-1280.png`, fullPage: true });
});

test("Só amigos closes the profile to a visitor and Público opens it again", async ({ page, browser }) => {
  await signIn(page);
  await page.goto("/u/e2e");
  await page.locator("#profile-visibility label", { hasText: "Só amigos" }).click();
  await expect(page.locator("#profile-visibility input[value='friends']")).toBeChecked();

  const visitor = await browser.newPage();
  await visitor.goto("/u/e2e");
  await expect(visitor.locator("#profile-closed")).toHaveText("Perfil só para amigos.");
  await expect(visitor.locator("#follow-button")).toHaveText("Seguir");

  await page.locator("#profile-visibility label", { hasText: "Público" }).click();
  await expect(page.locator("#profile-visibility input[value='public']")).toBeChecked();
  await visitor.reload();
  await expect(visitor.locator("#profile-closed")).toHaveCount(0);
  await expect(visitor.locator("#profile-head h1")).toHaveText("E2e");
  await visitor.close();
});

test("Ver diário opens the Diário, one row per change, and Mais N opens the rest", async ({ page }) => {
  await signIn(page);
  await page.goto("/u/e2e");
  await page.locator("#profile-diary-link").click();
  await expect(page).toHaveURL(/\/u\/e2e\/diario$/);

  const rows = page.locator("#diary .dk-entry:not(.dk-entry--more)");
  await expect(rows.first().locator(".dk-date")).toBeVisible();
  await expect(page.locator("#diary .dk-date--soon")).toHaveCount(0);
  await expect(page.getByText("R$")).toHaveCount(0);

  const more = page.locator("#diary .dk-entry--more .dk-link").first();
  await expect(more).toContainText("neste dia");
  const before = await rows.count();
  await more.click();
  await expect.poll(() => rows.count()).toBeGreaterThan(before);
  if (shots) await page.screenshot({ path: `${shots}/diario-1280.png`, fullPage: true });
});

test.describe("on a phone", () => {
  test.use({ viewport: { width: 375, height: 800 }, hasTouch: true, isMobile: true });

  test("the profile, the followers and the Diário fit at 375", async ({ page }) => {
    await signIn(page);
    await page.goto("/u/amiga");
    await expect(page.locator("#profile-head")).toBeVisible();
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBe(375);
    if (shots) await page.screenshot({ path: `${shots}/perfil-amiga-375.png`, fullPage: true });

    await page.goto("/u/e2e/seguidores");
    await expect(page.locator("#person-amiga")).toBeVisible();
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBe(375);
    if (shots) await page.screenshot({ path: `${shots}/seguidores-375.png`, fullPage: true });

    await page.goto("/u/e2e/diario");
    await expect(page.locator("#diary .dk-entry").first()).toBeVisible();
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBe(375);
    if (shots) await page.screenshot({ path: `${shots}/diario-375.png` });
  });
});
