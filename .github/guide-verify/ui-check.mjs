// The notebook's pages the way a reader sees them in a browser, for the guide's first-setup,
// check-it-works, folders-and-settings, backups-and-devices and troubleshooting pages. It needs
// no AI account: it reads every page, opens every Settings section, and presses only buttons that
// stay on this machine (Test and connect with empty or http fields, Check saved connections now,
// Save a backup, Restore a separate copy, Rebuild search). Evidence only; it never fails the job.
//
//   CHANNEL=chrome|msedge EVIDENCE=evidence node ui-check.mjs
import {chromium} from 'playwright-core';
import fs from 'node:fs';

const base = process.env.BASE || 'http://127.0.0.1:47831';
const out = process.env.EVIDENCE || 'evidence';
fs.mkdirSync(out, {recursive: true});
const browser = await chromium.launch({channel: process.env.CHANNEL || 'chrome', headless: true});
const page = await browser.newPage({viewport: {width: 1400, height: 1000}});
const log = (...a) => console.log(...a);
const text = () => page.evaluate(() => document.body.innerText);
const shot = name => page.screenshot({path: `${out}/ui-${name}.png`, fullPage: true}).catch(e => log('no picture', e.message));
const settle = async (ms = 4000) => { await page.waitForLoadState('networkidle', {timeout: 15000}).catch(() => {}); await page.waitForTimeout(ms); };
const added = (before, after) => { const seen = new Set(before.split('\n')); return after.split('\n').filter(l => l.trim() && !seen.has(l)).join('\n'); };
async function step(name, fn) { log(`\n===== UI: ${name}`); try { await fn(); } catch (e) { log(`ERROR in "${name}": ${String(e.message).split('\n')[0]}`); } }
async function openAll() { await page.evaluate(() => document.querySelectorAll('details').forEach(d => { d.open = true; })); await page.waitForTimeout(1000); }
// Presses a button and reports every line that appeared on the page afterwards, sampled every
// half second, so a message that shows for a few seconds and goes (a toast) is caught too.
async function press(name, waitFor, ms = 60000) {
  const before = await text();
  const seen = new Set();
  const sample = async () => { for (const l of added(before, await text()).split('\n')) if (l.trim()) seen.add(l); };
  await page.getByRole('button', {name, exact: true}).first().click();
  const until = Date.now() + (waitFor ? ms : 8000);
  while (Date.now() < until) {
    await sample();
    if (waitFor && [...seen].some(l => l.includes(waitFor))) { await page.waitForTimeout(1500); await sample(); break; }
    await page.waitForTimeout(500);
  }
  if (waitFor && ![...seen].some(l => l.includes(waitFor))) log(`(no "${waitFor}" within ${ms / 1000} s)`);
  log(`after pressing "${name}", new lines on the page:\n` + [...seen].join('\n'));
}

await step('the address the Start menu opens: /', async () => {
  const r = await page.goto(base + '/'); await settle();
  log('status', r && r.status(), 'final address', page.url());
});
await step('dashboard', async () => {
  await page.goto(base + '/dashboard'); await settle(8000);
  log(await text()); await shot('dashboard');
});
await step('the sidebar entries with their links', async () => {
  const links = await page.evaluate(() => [...document.querySelectorAll('a, button')].filter(e => e.offsetParent !== null).map(e => `${e.tagName} "${e.innerText.trim().replace(/\s+/g, ' ')}" ${e.getAttribute('href') || ''}`).filter(l => !l.includes('""')));
  log(links.join('\n'));
});
await step('Documentation in the sidebar', async () => {
  await page.getByText('Documentation', {exact: true}).first().click(); await settle();
  log('address', page.url()); log((await text()).slice(0, 1200)); await shot('documentation');
});
await step('Connect AI in the sidebar', async () => {
  await page.goto(base + '/dashboard'); await settle();
  await page.getByText('Connect AI', {exact: true}).first().click(); await settle();
  log('address', page.url(), 'scrolled to', await page.evaluate(() => scrollY));
  log((await text()).slice(0, 600));
});
await step('Settings, sections closed', async () => {
  await page.goto(base + '/dashboard/settings'); await settle(8000);
  log(await text()); await shot('settings-closed');
  const outline = await page.evaluate(() => [...document.querySelectorAll('summary, h1, h2, h3, h4')].map(e => `${e.tagName}: ${e.innerText.trim().split('\n')[0]}`));
  log('OUTLINE (top to bottom):\n' + outline.join('\n'));
});
await step('Settings, every section open', async () => {
  await openAll(); log(await text()); await shot('settings-open');
  const fields = await page.evaluate(() => [...document.querySelectorAll('input, textarea, select')].map(e => {
    const lab = (e.id && document.querySelector(`label[for="${CSS.escape(e.id)}"]`)) || e.closest('label');
    const opts = e.tagName === 'SELECT' ? ' options=' + [...e.options].map(o => o.text).join(' | ') : '';
    return `${e.tagName} type=${e.type || ''} label="${lab ? lab.innerText.trim().split('\n')[0] : (e.getAttribute('aria-label') || '')}" placeholder="${e.placeholder || ''}" value="${e.type === 'password' ? '(hidden)' : (e.value || '')}"${opts}`;
  }));
  log('FIELDS:\n' + fields.join('\n'));
});
await step('Connect your assistant: Test and connect with model name and key empty', async () => {
  log('the button is enabled:', await page.getByRole('button', {name: 'Test and connect', exact: true}).first().isEnabled());
  await press('Test and connect', null);
  const invalid = await page.evaluate(() => [...document.querySelectorAll('input:invalid, textarea:invalid, select:invalid')].map(e => `${e.getAttribute('aria-label') || e.name || e.id || e.type}: ${e.validationMessage}`));
  log('boxes the browser itself refuses (required fields):', invalid.join(' | ') || 'none');
});
await step('Connect your assistant: an http:// endpoint', async () => {
  await openAll();
  const fill = async (label, value) => { const f = page.getByLabel(label, {exact: false}).first(); await f.fill(value); };
  await fill('Model endpoint', 'http://example.com/v1/chat/completions');
  await fill('Model name', 'test-model');
  await fill('API key', 'not-a-real-key');
  await press('Test and connect', null);
  await page.reload(); await settle(6000); await openAll();
});
await step('Check saved connections now', async () => { await press('Check saved connections now', null); });
await step('Routines line and Recovery line', async () => {
  const t = await text();
  log(t.split('\n').filter(l => /Schedule owner|Assistant:|Last file scan|Conflicts waiting|Runs every|Paused/.test(l)).join('\n'));
});
await step('Recovery: Save a backup', async () => { await press('Save a backup', 'The backup was saved', 120000); });
await step('Recovery: choose the backup and Restore a separate copy', async () => {
  await page.reload(); await settle(6000); await openAll();
  const select = page.locator('select').filter({has: page.locator('option', {hasText: /backup/i})}).last();
  const options = await select.evaluate(s => [...s.options].map(o => `${o.value} | ${o.text}`));
  log('Choose a backup offers:\n' + options.join('\n'));
  const value = await select.evaluate(s => [...s.options].map(o => o.value).find(v => v));
  if (value) await select.selectOption(value);
  await press('Restore a separate copy', 'Restored and checked', 180000);
  await shot('settings-restored');
});
await step('Recovery: Rebuild search', async () => { await press('Rebuild search', null); });
await step('Open the Windows assistant', async () => { await openAll(); await press('Open the Windows assistant', null); });
await step('the dashboard again, after a minute (the Godspeed card)', async () => {
  await page.goto(base + '/dashboard'); await settle(15000);
  const t = await text(); log(t.slice(0, 1500)); await shot('dashboard-later');
});
await step('Chat with Godspeed (opened, nothing sent)', async () => {
  await page.getByText('Chat with Godspeed', {exact: true}).first().click(); await settle(6000);
  log('address', page.url()); log((await text()).slice(0, 1500)); await shot('chat');
});
await step("Godspeed's brain", async () => {
  await page.goto(base + '/dashboard'); await settle();
  await page.getByText("Godspeed's brain", {exact: true}).first().click(); await settle(6000);
  log('address', page.url()); log((await text()).slice(0, 2500)); await shot('brain');
});
await step('Notes', async () => {
  await page.goto(base + '/dashboard'); await settle();
  await page.getByText('Notes', {exact: true}).first().click(); await settle(6000);
  log('address', page.url()); log((await text()).slice(0, 1500));
});
await browser.close();
log('\nui-check done');
