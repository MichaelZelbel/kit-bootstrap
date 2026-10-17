// The newcomer path of the rewritten guide (godspeedmissioncontrol.com/guide, 18 October 2026),
// in a browser, on a fresh machine, after the install: open the notebook, give the first goal in
// Settings, see the routines it starts. No AI account: nothing here sends a chat message.
// Takes the pictures the guide's pages use, at a laptop's size (1280 x 800).
//
//   CHANNEL=chrome|msedge EVIDENCE=evidence [WINDOWS=1] node newcomer-walk.mjs
import {chromium} from 'playwright-core';
import fs from 'node:fs';

const base = process.env.BASE || 'http://127.0.0.1:47831';
const out = process.env.EVIDENCE || 'evidence';
fs.mkdirSync(out, {recursive: true});
const browser = await chromium.launch({channel: process.env.CHANNEL || 'chrome', headless: true});
const page = await browser.newPage({viewport: {width: 1280, height: 800}, deviceScaleFactor: 2});
const log = (...a) => console.log(...a);
const text = () => page.evaluate(() => document.body.innerText);
const shot = (name, opts = {}) => page.screenshot({path: `${out}/walk-${name}.png`, ...opts}).catch(e => log('no picture', e.message));
const settle = async (ms = 4000) => { await page.waitForLoadState('networkidle', {timeout: 20000}).catch(() => {}); await page.waitForTimeout(ms); };
async function step(name, fn) { log(`\n===== ${name}`); try { await fn(); } catch (e) { log(`ERROR in "${name}": ${String(e.message).split('\n')[0]}`); } }

await step('Open your notebook: the dashboard', async () => {
  const t0 = Date.now();
  for (;;) { try { const r = await page.goto(base + '/dashboard'); if (r && r.ok()) break; } catch {} if (Date.now() - t0 > 180000) throw new Error('the notebook did not answer within 3 minutes'); await page.waitForTimeout(5000); }
  await settle(10000);
  const t = await text(); log(t.slice(0, 2500));
  log('has "Your notebook":', t.includes('Your notebook'), '| has "Chat with Godspeed":', t.includes('Chat with Godspeed'));
  await shot('01-dashboard');
});

await step('Settings before the first goal', async () => {
  await page.goto(base + '/dashboard/settings'); await settle(8000);
  const t = await text(); log(t.slice(0, 1500));
  log('has "Start with one goal":', t.includes('Start with one goal'));
  const form = page.locator('form', {hasText: 'Start with one goal'}).first();
  await form.scrollIntoViewIfNeeded().catch(() => {});
  await form.screenshot({path: `${out}/walk-02-start-with-one-goal.png`}).catch(e => log('no picture', e.message));
  if (process.env.WINDOWS) {
    const b = page.getByRole('button', {name: 'Open the Windows assistant', exact: true}).first();
    log('"Open the Windows assistant" is there:', await b.count() > 0);
  }
});

await step('Give it a goal: What matters to you?, Timezone, Start', async () => {
  await page.getByLabel('What matters to you?').fill('Run 10 km without stopping by June');
  log('Timezone box says:', await page.getByLabel('Timezone').inputValue());
  await page.getByRole('button', {name: 'Start', exact: true}).first().click();
  await page.waitForTimeout(15000); await page.reload(); await settle(8000);
  const t = await text();
  log('"Start with one goal" still shown:', t.includes('Start with one goal'));
  const i = t.indexOf('Your goals and follow-through');
  log('under "Your goals and follow-through":\n' + (i >= 0 ? t.slice(i, i + 600) : '(heading not found)'));
  log('the goal is listed:', t.includes('Run 10 km without stopping by June'));
});

await step('See it working: Settings, Routines', async () => {
  let rows = [];
  for (let i = 0; i < 8; i++) {
    await page.reload(); await settle(6000);
    await page.evaluate(() => document.querySelectorAll('details').forEach(d => { d.open = true; }));
    const t = await text();
    const at = t.indexOf('\nRoutines\n');
    const part = at >= 0 ? t.slice(at, at + 3000) : t;
    rows = part.split('\n').filter(l => /Runs |Next run|every|Sundays|Last ran|Paused/i.test(l));
    if (rows.length >= 6) break;
    await page.waitForTimeout(15000);
  }
  log(`routine lines (${rows.length}):\n` + rows.join('\n'));
  const section = page.locator('section', {has: page.locator('h2', {hasText: /^Routines$/})}).first();
  await section.scrollIntoViewIfNeeded().catch(() => {});
  await section.screenshot({path: `${out}/walk-03-routines.png`}).catch(e => log('no picture', e.message));
  const t = await text(); const at = t.indexOf('\nRoutines\n'); log('Routines section text:\n' + (at >= 0 ? t.slice(at, at + 2500) : '(not found)'));
});

await step('Notes: the sidebar, and the folder From your routines', async () => {
  await page.goto(base + '/dashboard'); await settle();
  const nav = await page.evaluate(() => [...document.querySelectorAll('nav a, aside a')].map(a => a.innerText.trim()).filter(Boolean));
  log('sidebar:', nav.join(' | '));
});

await step('Chat with Godspeed (opened, nothing sent)', async () => {
  await page.goto(base + '/dashboard'); await settle();
  await page.getByText('Chat with Godspeed', {exact: true}).first().click(); await settle(6000);
  log('address', page.url()); log((await text()).slice(0, 1200)); await shot('04-chat');
});

if (process.env.WINDOWS) {
  await step('Open the Windows assistant (the Hermes app opens outside the browser)', async () => {
    await page.goto(base + '/dashboard/settings'); await settle(8000);
    const before = await text();
    await page.getByRole('button', {name: 'Open the Windows assistant', exact: true}).first().click();
    await page.waitForTimeout(20000);
    const after = await text();
    const seen = new Set(before.split('\n'));
    log('new lines on the page:\n' + after.split('\n').filter(l => l.trim() && !seen.has(l)).join('\n'));
  });
}

await step('Phone width: the dashboard at 390 px', async () => {
  const phone = await browser.newPage({viewport: {width: 390, height: 844}, deviceScaleFactor: 3});
  await phone.goto(base + '/dashboard'); await phone.waitForTimeout(8000);
  await phone.screenshot({path: `${out}/walk-05-dashboard-phone.png`}).catch(() => {});
  await phone.close();
});

await browser.close();
