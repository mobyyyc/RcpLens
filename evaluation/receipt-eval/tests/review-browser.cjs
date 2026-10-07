// Optional local browser regression. Uses fictional fixture page only; no screenshots/DOM dumps.
const { chromium } = require('playwright');
const { pathToFileURL } = require('node:url');
const path = require('node:path');
const assert = require('node:assert/strict');
(async () => {
  const browser = await chromium.launch({headless:true, executablePath:process.env.RCPLENS_BROWSER || chromium.executablePath()});
  try {
    const page = await browser.newPage({viewport:{width:1440,height:900}});
    let requests = 0;
    page.on('request', r => { if (/^https?:/.test(r.url())) requests++; });
    await page.goto(pathToFileURL(path.resolve('private-receipts/evaluation/synthetic-final/review.html')).href);
    assert.equal(await page.locator('article').count(),6);
    assert.equal(await page.locator('tbody tr').count(),0);
    await page.locator('.draft').first().click();
    assert.ok(await page.locator('article').first().locator('tbody tr').count()>0);
    assert.equal(await page.locator('article').first().locator('.checks input:checked').count(),0);
    await page.locator('article').first().locator('.checks input').evaluateAll(nodes=>nodes.forEach(n=>n.checked=true));
    await page.locator('article').first().locator('.field').first().fill('SYNTHETIC EDIT');
    assert.equal(await page.locator('article').first().locator('.checks input:checked').count(),0);
    await page.getByRole('button',{name:'Export human-verified labels'}).click();
    assert.match(await page.locator('#message').textContent(),/Verify all four checks/);
    await page.locator('.checks input').evaluateAll(nodes=>nodes.forEach(n=>n.checked=true));
    await page.locator('article').first().locator('tbody tr').first().locator('input').nth(1).fill('1.234');
    await page.locator('h1').click(); // Commit change/blur before human confirmations.
    await page.locator('.checks input').evaluateAll(nodes=>nodes.forEach(n=>n.checked=true));
    await page.getByRole('button',{name:'Export human-verified labels'}).click();
    assert.match(await page.locator('#message').textContent(),/two decimal places/);
    for(const button of await page.locator('.draft').all()) await button.click();
    await page.locator('.checks input').evaluateAll(nodes=>nodes.forEach(n=>n.checked=true));
    const downloadPromise=page.waitForEvent('download');
    await page.getByRole('button',{name:'Export human-verified labels'}).click();
    const download=await downloadPromise;
    const stream=await download.createReadStream();
    const parts=[];for await(const part of stream) parts.push(part);
    const labels=JSON.parse(Buffer.concat(parts).toString());
    assert.equal(labels.schema_version,1);assert.equal(labels.receipts.length,6);
    assert.ok(labels.receipts.every(r=>r.reviewed && r.verification_checks.amounts && r.expected.lines.every(l=>Number.isInteger(l.amount))));
    assert.equal(requests,0);
    console.log('review browser checks passed: blank/draft, verification reset, export gate, cent validation, no HTTP requests');
  } finally { await browser.close(); }
})().catch(e=>{console.error('synthetic review browser check: '+String(e.message).slice(0,700));process.exitCode=1;});
