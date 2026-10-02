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
  await expect(page.locator("#profile-edit")).toBeVisible();
  await expect(page.locator("#profile-visibility")).toHaveCount(0);
  await expect(page.locator("#follow-button")).toHaveCount(0);
  await expect(page.locator("#profile-numbers")).toContainText("Jogos");
  await expect(page.locator("#profile-stats")).toBeVisible();
  await expect(page.getByText("R$")).toHaveCount(0);
  if (shots) await page.screenshot({ path: `${shots}/perfil-1280.png`, fullPage: true });

  // Zerados and Quero moved off the personal card in the profile redesign (915c059);
  // they still show fully on their own routes.
  await page.goto("/u/e2e/zerados");
  await expect(page.locator("#profile-zerado-grid .dk-card")).toHaveCount(1);
  await expect(page.getByText("R$")).toHaveCount(0);

  await page.goto("/u/e2e/quero");
  await expect(page.locator("#profile-quero")).toBeVisible();
  await expect(page.getByText("R$")).toHaveCount(0);
});

test("Editar perfil leads to Configurações and the bio, place and link show on the profile", async ({ page }) => {
  await signIn(page);
  await page.goto("/u/e2e");
  await page.locator("#profile-edit").click();
  await expect(page).toHaveURL(/\/configuracoes$/);

  await page.locator("#settings-profile-form input[name='user[bio]']").fill("Zerando um jogo por vez");
  await page.locator("#settings-profile-form input[name='user[location]']").fill("Belém, Brasil");
  await page.locator("#settings-profile-form input[name='user[link]']").fill("e2e.example.com");
  await page.locator("#settings-profile-submit").click();
  await expect(page.locator("#settings-profile-notice")).toHaveText("Perfil atualizado");

  await page.goto("/u/e2e");
  await expect(page.locator("#profile-bio")).toHaveText("Zerando um jogo por vez");
  await expect(page.locator("#profile-location")).toHaveText("Belém, Brasil");
  await expect(page.locator("#profile-link")).toHaveText("e2e.example.com");
  await expect(page.locator("#profile-link")).toHaveAttribute("href", "https://e2e.example.com");
});

test("favorites live on the profile: X on hover, + opens the search, drag and arrows order them", async ({ page }) => {
  await signIn(page);
  await page.goto("/u/e2e");
  await expect(page.locator("#profile-edit-favorites")).toHaveCount(0);

  // start empty: earlier runs may have left favorites behind
  while ((await page.locator(".dk-fav-remove").count()) > 0) {
    const slot = page.locator(".dk-fav-slot[data-game-id]").first();
    await slot.hover();
    await slot.locator(".dk-fav-remove").click();
  }
  await expect(page.locator("#favorite-add-1")).toBeVisible();

  const choose = async (position: number, query: string) => {
    await page.locator(`#favorite-add-${position}`).click();
    await expect(page.locator("#favorite-picker")).toBeVisible();
    await page.locator("#favorite-search").fill(query);
    await page.locator("#favorite-results .dk-row").filter({ hasText: query }).locator("button").click();
    await expect(page.locator("#favorite-picker")).toHaveCount(0);
    await expect(page.locator(`#favorite-add-${position}`)).toBeFocused();
  };

  await choose(1, "Store Quest");
  await choose(2, "Sale Quest");
  await expect(page.locator("#profile-favorites-grid .dk-fav-slot[data-game-id]")).toHaveCount(2);

  // the X shows on hover only
  const first = page.locator(".dk-fav-slot[data-position='1']");
  const x = first.locator(".dk-fav-remove");
  await page.mouse.move(0, 0);
  await expect(x).toHaveCSS("opacity", "0");
  await first.hover();
  await expect(x).toHaveCSS("opacity", "1");

  // dragging the first cover onto the second swaps them
  const title = (position: number) => page.locator(`.dk-fav-slot[data-position='${position}'] .dk-card__title`);
  await expect(title(1)).toHaveText("Store Quest");
  const from = await first.locator(".dk-poster").boundingBox();
  const to = await page.locator(".dk-fav-slot[data-position='2'] .dk-poster").boundingBox();
  await page.mouse.move(from!.x + from!.width / 2, from!.y + from!.height / 2);
  await page.mouse.down();
  await page.mouse.move(to!.x + to!.width / 2, to!.y + to!.height / 2, { steps: 8 });
  await page.mouse.up();
  await expect(title(1)).toHaveText("Sale Quest");
  await expect(title(2)).toHaveText("Store Quest");
  await expect(page).toHaveURL(/\/u\/e2e$/);

  // the arrow keys move the focused cover one position
  await page.locator(".dk-fav-slot[data-position='2'] .dk-poster").focus();
  await page.keyboard.press("ArrowLeft");
  await expect(title(1)).toHaveText("Store Quest");
  await expect(page.locator(".dk-fav-slot[data-position='1'] .dk-poster")).toBeFocused();
  if (shots) {
    await first.hover();
    await page.screenshot({ path: `${shots}/favoritos-1280.png`, fullPage: true });
  }

  await page.locator("#favorite-add-3").click();
  const search = page.locator("#favorite-search");
  const close = page.locator("#favorite-picker-close");
  await expect(search).toBeFocused();
  await page.keyboard.press("Shift+Tab");
  await expect(close).toBeFocused();
  await page.keyboard.press("Tab");
  await expect(search).toBeFocused();
  await page.locator("#favorite-search").fill("Friendly");
  await expect(page.locator("#favorite-results .dk-row").first()).toBeVisible();
  if (shots) await page.screenshot({ path: `${shots}/favoritos-modal-1280.png` });
  const lastResult = page.locator("#favorite-results .dk-row button").last();
  await lastResult.focus();
  await page.keyboard.press("Tab");
  await expect(close).toBeFocused();
  await page.keyboard.press("Shift+Tab");
  await expect(lastResult).toBeFocused();
  await page.keyboard.press("Escape");
  await expect(page.locator("#favorite-picker")).toHaveCount(0);
  await expect(page.locator("#favorite-add-3")).toBeFocused();

  for (const position of [1, 2]) {
    const slot = page.locator(`.dk-fav-slot[data-position='${position}']`);
    await slot.hover();
    await slot.locator(".dk-fav-remove").click();
  }
  await expect(page.locator(".dk-fav-remove")).toHaveCount(0);
  await expect(page.getByText("Remover favorito")).toHaveCount(0);
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
  const card = page.locator("#profile-playing-now .dk-card").filter({ hasText: "Friendly Voyage" });
  await expect(card.locator(".dk-status--add")).toBeVisible();
  if (shots) await page.screenshot({ path: `${shots}/perfil-amiga-1280.png`, fullPage: true });
});

test("Só amigos closes the profile to a visitor and Público opens it again", async ({ page, browser }) => {
  await signIn(page);
  await page.goto("/configuracoes");
  await page.locator("#settings-visibility label", { hasText: "Só amigos" }).click();
  await expect(page.locator("#settings-visibility input[value='friends']")).toBeChecked();

  const visitor = await browser.newPage();
  await visitor.goto("/u/e2e");
  await expect(visitor.locator("#profile-closed")).toHaveText("Perfil só para amigos.");
  await expect(visitor.locator("#follow-button")).toHaveText("Seguir");

  await page.locator("#settings-visibility label", { hasText: "Público" }).click();
  await expect(page.locator("#settings-visibility input[value='public']")).toBeChecked();
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

    await page.goto("/u/e2e");
    await page.locator("#favorite-add-1").click();
    await page.locator("#favorite-search").fill("Store Quest");
    await expect(page.locator("#favorite-results .dk-row").first()).toBeVisible();
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBe(375);
    if (shots) await page.screenshot({ path: `${shots}/favoritos-modal-375.png` });
    await page.locator("#favorite-results .dk-row").first().locator("button").click();
    await expect(page.locator(".dk-fav-remove").first()).toHaveCSS("opacity", "0.8");
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBe(375);
    if (shots) await page.screenshot({ path: `${shots}/favoritos-375.png`, fullPage: true });
    await page.locator(".dk-fav-remove").first().click();
    await expect(page.locator(".dk-fav-remove")).toHaveCount(0);

    await page.goto("/u/e2e/diario");
    await expect(page.locator("#diary .dk-entry").first()).toBeVisible();
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBe(375);
    if (shots) await page.screenshot({ path: `${shots}/diario-375.png` });
  });
});
