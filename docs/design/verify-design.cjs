/* Focused browser walkthrough; uses an existing Playwright installation and Chrome. */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const playwrightPath = process.env.PLAYWRIGHT_MODULE || 'playwright';
const { chromium } = require(playwrightPath);
const chromePath = process.env.CHROME_EXECUTABLE || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const base = __dirname;
const findings = [];
const check = (label, value = true) => { assert.ok(value, label); findings.push(label); };
let reviewBrowser;
(async () => {
  const browser = reviewBrowser = await chromium.launch({executablePath:chromePath,headless:true});
  const page = await browser.newPage({viewport:{width:1100,height:1200}});
  const runtimeErrors = [];
  page.on('pageerror',e => runtimeErrors.push(e.message));
  await page.goto(`file://${path.join(base,'index.html')}`);
  const scenario = value => page.locator('#scenario').selectOption(value);
  const screenshot = name => page.locator('.concepts').screenshot({path:path.join(base,'evidence',name),animations:'disabled'});
  const app = id => page.locator(`#${id}`);
  check('Initial render: two concepts, three recent receipt buttons each', await page.locator('.slip').count()===6);
  const arithmetic = await page.evaluate(() => [5,50,500].every(n=>SlipletDesign.getReceipts(n).every(r=> r.status==='Saved' ? r.total===SlipletDesign.expectedTotal(r) : r.total-SlipletDesign.expectedTotal(r)===100)));
  check('Synthetic amounts reconcile; deliberate $1 discrepancies are marked Needs review',arithmetic);
  check('Decimal input parses cents exactly and rejects malformed amounts',await page.evaluate(()=>SlipletDesign.parseCents('12.34')===1234 && SlipletDesign.parseCents('0.01')===1 && SlipletDesign.parseCents('1.234')===null && SlipletDesign.parseCents('-1')===null));
  await screenshot('concepts-wallet.png');
  for (const count of [5,50,500]) {
    await page.locator('#collection').selectOption(String(count));
    await scenario('library');
    for (const id of ['pocket','paper']) {
      const root=app(id);
      check(`${id}: ${count} receipts, bounded initial page`,await root.locator('.receipt-row').count()===Math.min(count,25));
      await root.locator('.merchant-filter').selectOption('T&T');
      const filteredCount=Math.floor(count/3);
      check(`${id}: merchant filter in ${count} receipts`,(await root.locator('.result-count').textContent()).includes(`${filteredCount} receipt`));
      await root.locator('.merchant-filter').selectOption('');
      const monthOptions=await root.locator('.month-filter option').allTextContents();
      await root.locator('.month-filter').selectOption({index:monthOptions.length-1});
      check(`${id}: oldest month reachable directly with ${count} receipts`,await root.locator('.receipt-row').count()>0);
      await root.locator('.month-filter').selectOption('');
      await root.locator('.search-input').fill('豆腐');
      check(`${id}: bilingual item search in ${count} receipts`,await root.locator('.matched').first().textContent()==='Tofu · 豆腐 · $4.59' || (await root.locator('.matched').first().textContent()).startsWith('Tofu · 豆腐'));
      await root.locator('.search-input').fill('CC101');
      check(`${id}: SKU search in ${count} receipts`,await root.locator('.matched').count()>0);
      await root.locator('.search-input').fill('zzzz');
      check(`${id}: no-result recovery in ${count} receipts`,await root.getByRole('heading',{name:'No receipts found.'}).count()===1);
      await root.getByRole('button',{name:'Clear search and filters'}).click();
      if(count>25) {
        await root.getByRole('button',{name:'Show next 25 receipts'}).click();
        check(`${id}: next page reachable in ${count} receipts`,await root.locator('.receipt-row').count()===50);
      }
      await root.locator('.search-input').fill('milk');
      await root.locator('.receipt-row').first().click();
      check(`${id}: item search opens its receipt and marks matched item`,await root.locator('[data-search-match="true"]').count()===1);
      await root.getByRole('button',{name:'Original receipt View'}).click();
      check(`${id}: evidence reachable from search result`,await root.locator('.source-paper').count()===1);
    }
  }
  await page.locator('#collection').selectOption('50');
  await scenario('home');
  for(const id of ['pocket','paper']) {
    const root=app(id);
    await root.locator('.slip[data-position="0"]').click({position:{x:80,y:24}});
    check(`${id}: tap opens newest receipt`,await root.locator('.merchant').textContent()==='No Frills');
    await root.getByRole('button',{name:'Edit',exact:true}).click();
    await root.locator('[data-item="0"][data-field="amount"]').fill('7.49');
    check(`${id}: discrepancy blocks Save and shows exact $1 difference`,await root.locator('.save').isDisabled() && (await root.locator('.reconcile').textContent()).includes('$1.00 difference'));
    await root.locator('[data-field="total"]').fill('23.40');
    check(`${id}: corrected total permits Save`,await root.locator('.save').isEnabled());
    await root.locator('[data-field="tax"]').fill('1.234');
    check(`${id}: invalid decimal blocks Save`,await root.locator('.save').isDisabled());
    await root.locator('[data-field="tax"]').fill('1.43');
    await root.getByRole('button',{name:'Save receipt',exact:true}).click();
    check(`${id}: edited amount appears in detail`,(await root.locator('.receipt-line').first().textContent()).includes('$7.49'));
    await root.getByRole('button',{name:'Original receipt View'}).click();
    check(`${id}: original is unchanged by digital edit`,(await root.locator('.source-paper').textContent()).includes('6.49') && (await root.locator('.source-paper').textContent()).includes('22.40'));
  }
  await page.locator('#collection').selectOption('5');await page.locator('#collection').selectOption('50');await scenario('detail');await screenshot('receipt-detail.png');
  await scenario('home');
  for(const id of ['pocket','paper']) {
    const slip=app(id).locator('.slip[data-position="0"]');const box=await slip.boundingBox();
    await page.mouse.move(box.x+90,box.y+30);await page.mouse.down();await page.mouse.move(box.x+90,box.y-50,{steps:8});await page.mouse.up();
    check(`${id}: upward pull opens the receipt`,await app(id).locator('.merchant').count()===1);
  }
  await scenario('processing');
  for(const id of ['pocket','paper']) {
    await app(id).getByRole('button',{name:'Back'}).click();
    check(`${id}: processing can be left and reopened`,await app(id).getByRole('button',{name:'Reading receipt… Open'}).count()===1);
    await app(id).getByRole('button',{name:'Reading receipt… Open'}).click();
  }
  await page.locator('#finish-reading').click();
  for(const id of ['pocket','paper']) {
    check(`${id}: imported flagged item requires confirmation`,await app(id).locator('.save').isDisabled());
    await app(id).locator('[data-item="0"][data-field="name"]').fill('Milk · 2 L');
    await app(id).locator('.review-confirm').check();
    await app(id).getByRole('button',{name:'Save receipt',exact:true}).click();
    check(`${id}: import review saves a synthetic receipt`,await app(id).locator('.merchant').count()===1);
  }
  await scenario('error');await screenshot('reading-failed.png');
  for(const id of ['pocket','paper']) {
    await app(id).getByRole('button',{name:'Original receipt View'}).click();
    check(`${id}: failed import retains evidence access`,await app(id).locator('.source-paper').count()===1);
    await app(id).getByRole('button',{name:'Back'}).click();
    await app(id).getByRole('button',{name:'Enter manually'}).click();
    check(`${id}: manual entry has a blank reviewable draft`,await app(id).locator('[data-field="merchant"]').inputValue()==='' && await app(id).locator('.save').isDisabled());
  }
  await scenario('empty');await screenshot('empty-wallet.png');
  check('Empty state offers an import action in both concepts',await page.getByRole('button',{name:'Import a receipt',exact:true}).count()===2);
  // Review requested extremes without pretending CSS scaling is native Dynamic Type.
  for(const size of ['small','large']) for(const scale of ['1','2']) for(const state of ['home','library','detail','edit','processing','error','empty','search','nomatch']) {
    await page.locator('#screen-size').selectOption(size);
    await page.locator('#text-size').selectOption(scale);
    await scenario(state);
    const overflow = await page.evaluate(()=>[...document.querySelectorAll('.phone,.phone .content')].filter(e=>e.scrollWidth>e.clientWidth+1).map(e=>e.className));
    check(`${size}, ${scale==='2'?'200%':'default'} text, ${state}: no horizontal overflow`,overflow.length===0);
  }
  await page.locator('#collection').selectOption('500');
  await page.locator('#screen-size').selectOption('small');await page.locator('#text-size').selectOption('2');await scenario('library');
  await screenshot('small-large-text-library.png');
  await page.locator('#screen-size').selectOption('large');await page.locator('#text-size').selectOption('1');await page.locator('#appearance').selectOption('dark');await scenario('search');
  await screenshot('large-dark-search.png');
  await page.locator('#reduce-motion').check();await scenario('home');
  for(const id of ['pocket','paper']) {
    check(`${id}: Reduce Motion replaces pull hint with tap`,await app(id).locator('.pull-hint').textContent()==='Tap a receipt to open.');
    await app(id).locator('.slip[data-position="0"]').click({position:{x:80,y:24}});
    check(`${id}: Reduce Motion retains tap and disables opening animation`,await app(id).locator('.open-motion').evaluate(e=>getComputedStyle(e).animationName)==='none');
  }
  await page.locator('#reduce-motion').uncheck();await page.emulateMedia({reducedMotion:'reduce'});await page.waitForFunction(()=>document.querySelectorAll('.phone.reduce').length===2);await scenario('home');
  check('OS/browser reduced-motion preference is honored without demo checkbox',await page.locator('.phone.reduce').count()===2);
  // Inspect accessible names and keyboard activation, not a claim of actual VoiceOver testing.
  await page.locator('#screen-size').selectOption('small');await page.locator('#text-size').selectOption('2');await page.locator('#appearance').selectOption('light');await scenario('home');
  const recent = app('pocket').locator('.slip[data-position="0"]');
  check('Receipt button accessible name includes merchant/date/amount/state',(await recent.getAttribute('aria-label')).includes('No Frills, Oct 7, 2026, $22.40, Saved'));
  await recent.focus();await page.keyboard.press('Enter');
  check('Keyboard activation opens a receipt without dragging',await app('pocket').locator('.merchant').count()===1);
  check('No JavaScript runtime errors',runtimeErrors.length===0);
  fs.writeFileSync(path.join(base,'evidence','browser-checks.json'),JSON.stringify({reviewedAt:new Date().toISOString(),browser:await browser.version(),checksPassed:findings.length,checks:findings,limitations:['Browser HTML/CSS prototype only; no native simulator Dynamic Type, VoiceOver or production performance validation.','Imported evidence is a synthetic transcription placeholder, not a real receipt image.','Screenshots are design evidence; not proof of native iOS 27 pixel fidelity.']},null,2)+'\n');
  console.log(`${findings.length} design walkthrough checks passed; screenshots and JSON saved under docs/design/evidence.`);
  await browser.close();
})().catch(async e=>{console.error(e);process.exitCode=1;await reviewBrowser?.close();});
