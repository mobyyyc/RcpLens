/* Standalone, synthetic design study. No receipt inputs, network calls or persistence. */
'use strict';
(() => {
  const merchantNames = ['No Frills', 'Costco', 'T&T'];
  const catalogue = [
    [{ name: 'Milk · 2 L', raw: 'MILK 2L', sku: 'NF001', amount: 649, quantity: '1 carton' }, { name: 'Bananas', raw: 'BANANAS', sku: 'NF002', amount: 349, quantity: '1 bunch' }, { name: 'Ground coffee', raw: 'GRND COFFEE', sku: 'NF003', amount: 1299, quantity: '1 bag' }],
    [{ name: 'Laundry detergent', raw: 'LAUNDRY DETERG', sku: 'CC101', amount: 1599, quantity: '1 bottle' }, { name: 'Jasmine rice', raw: 'JASM RICE', sku: 'CC102', amount: 2399, quantity: '1 bag' }, { name: 'Eggs', raw: 'EGGS 24', sku: 'CC103', amount: 699, quantity: '1 carton' }],
    [{ name: 'Tofu · 豆腐', raw: 'TOFU 豆腐', sku: 'TT201', amount: 459, quantity: '1 pack' }, { name: 'Pork dumplings', raw: 'PORK DUMPL', sku: 'TT202', amount: 899, quantity: '1 bag' }, { name: 'Asian pears · 梨', raw: 'ASIAN PEAR 梨', sku: 'TT203', amount: 679, quantity: '1 pack' }]
  ];
  const clone = value => JSON.parse(JSON.stringify(value));
  const cents = value => { const s = String(value).trim(); return /^(0|[1-9]\d{0,6})(\.\d{1,2})?$/.test(s) ? Number(s.split('.')[0]) * 100 + Number((s.split('.')[1] || '').padEnd(2,'0')) : null; };
  const decimal = value => `${Math.floor(value / 100)}.${String(value % 100).padStart(2,'0')}`;
  const money = value => `${value < 0 ? '−' : ''}$${decimal(Math.abs(value))}`;
  const sum = receipt => receipt.items.reduce((n,item) => n + item.amount,0);
  const expected = receipt => sum(receipt) - receipt.discount + receipt.tax;
  const esc = value => String(value).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const dateLabel = value => new Date(`${value}T12:00:00Z`).toLocaleDateString('en-CA',{month:'short',day:'numeric',year:'numeric',timeZone:'UTC'});
  const monthLabel = value => new Date(`${value}-01T12:00:00Z`).toLocaleDateString('en-CA',{month:'long',year:'numeric',timeZone:'UTC'});
  function makeReceipts(count) {
    return Array.from({length:count},(_,i) => {
      const merchant = i % 3;
      const date = new Date(Date.UTC(2026,9,7-i*2)).toISOString().slice(0,10);
      const items = clone(catalogue[merchant]);
      items[0].amount += (i % 7) * 25;
      const receipt = {id:`S${String(i+1).padStart(3,'0')}`, merchant:merchantNames[merchant], date, items, discount:[200,400,100][merchant], tax:[143,559,97][merchant], total:0, status:'Saved'};
      receipt.total = expected(receipt);
      if (i % 17 === 16) { receipt.total += 100; receipt.status = 'Needs review'; }
      receipt.original = clone(receipt);
      return receipt;
    });
  }
  const icons = {
    wallet:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" aria-hidden="true"><rect x="3" y="5" width="18" height="15" rx="3"/><path d="M3 9h18M16 13h5M17 16h1"/></svg>',
    receipts:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" aria-hidden="true"><path d="M6 3h12v18l-3-2-3 2-3-2-3 2V3Z"/><path d="M9 8h6M9 12h6"/></svg>',
    search:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" aria-hidden="true"><circle cx="10.5" cy="10.5" r="6.5"/><path d="m15.5 15.5 5 5"/></svg>'
  };
  const settings = {count:50,size:'regular',scale:1,reduce:false,appearance:'light'};
  const apps = ['pocket','paper'].map(id => ({id,root:document.getElementById(id),receipts:makeReceipts(50),view:'home',returnView:'home',selected:'S001',query:'',merchant:'',month:'',limit:25,pending:false,draft:null,editingOriginal:null,importing:false,sourceReturn:'detail',empty:false,focusItem:null}));
  function selected(app) { return app.receipts.find(receipt => receipt.id === app.selected) || app.receipts[0]; }
  function announce(app,text) { const region = app.root.querySelector('.announcement'); if(region) region.textContent = text; }
  function toolbar(app) {
    if (['detail','edit','source','processing','error'].includes(app.view)) {
      const back = app.view === 'edit' ? 'Cancel' : app.view === 'source' ? 'Back' : 'Back';
      const action = app.view === 'edit' ? '' : app.view === 'detail' ? '<button type="button" class="nav-action" data-action="edit">Edit</button>' : '';
      const title = {detail:'Receipt',edit:app.importing?'Review':'Edit',source:'Original',processing:'Import',error:'Import'}[app.view];
      return `<button type="button" class="nav-action" data-action="back">‹ ${back}</button><span class="toolbar-title">${title}</span>${action}`;
    }
    return `<span class="micro">RcpLens</span><button type="button" class="nav-action import" data-action="import" aria-label="Import a receipt image">＋ Import</button>`;
  }
  function tabbar(app) {
    if (['edit','source','processing','error','detail'].includes(app.view)) return '';
    return `<nav class="tabbar" aria-label="App navigation">${[['home','Wallet','wallet'],['library','Receipts','receipts'],['search','Search','search']].map(([view,name,icon])=>`<button type="button" class="tab" data-action="navigate" data-view="${view}" ${app.view===view?'aria-current="page"':''}>${icons[icon]}<span>${name}</span></button>`).join('')}</nav>`;
  }
  function slip(receipt,position,app) {
    return `<button type="button" class="slip" data-position="${position}" data-action="open" data-id="${receipt.id}" aria-label="Open ${esc(receipt.merchant)}, ${dateLabel(receipt.date)}, ${money(receipt.total)}, ${receipt.status}" aria-describedby="${app.id}-pull"><span class="slip-header"><span><span class="slip-name">${esc(receipt.merchant)}</span><span class="slip-date" style="display:block">${dateLabel(receipt.date)}</span></span><span class="amount">${money(receipt.total)}</span></span>${position===0?`<span class="slip-items">${receipt.items.slice(0,2).map(item=>`<span><span>${esc(item.name)}</span><span>${money(item.amount)}</span></span>`).join('')}</span>${app.id==='paper'?`<span class="paper-total"><span>3 items · CAD</span><span>Open receipt ↑</span></span>`:''}`:''}</button>`;
  }
  function home(app) {
    if (app.empty || !app.receipts.length) return `<h1>Wallet</h1><div class="empty"><div class="empty-symbol">${icons.wallet}</div><h2>Your first receipt<br>belongs here.</h2><p class="secondary">Import a receipt image. Review its details, then keep it close for later.</p><button type="button" class="primary" data-action="import">Import a receipt</button></div>`;
    const recent = app.receipts.slice(0,3);
    return `<h1>Wallet</h1><p class="secondary">${app.receipts.length} receipts, one place.</p>${app.pending?'<button type="button" class="evidence-link" data-action="processing">Reading receipt… <span>Open ›</span></button>':''}<div class="wallet-stage" role="group" aria-label="Three recent receipts">${recent.map((r,i)=>slip(r,i,app)).join('')}<div class="pocket-face" aria-hidden="true"><span>Recent receipts</span><span>${Math.min(3,app.receipts.length)} / ${app.receipts.length}</span></div></div><p class="pull-hint" id="${app.id}-pull">${settings.scale>=1.5 || motionReduced()?'Tap a receipt to open.':'Pull up or tap a receipt to open.'}</p><button type="button" class="evidence-link" data-action="navigate" data-view="library"><span>All receipts</span><span>${app.receipts.length} ›</span></button>`;
  }
  function filtered(app) {
    if (app.empty) return [];
    const q = app.query.toLocaleLowerCase().trim();
    return app.receipts.filter(r => (!app.merchant || r.merchant === app.merchant) && (!app.month || r.date.startsWith(app.month)) && (!q || [r.merchant,...r.items.flatMap(i=>[i.name,i.raw,i.sku])].join(' ').toLocaleLowerCase().includes(q)));
  }
  function matchLabel(receipt,query) {
    if(!query.trim()) return '';
    const item = receipt.items.find(i=>[i.name,i.raw,i.sku].join(' ').toLocaleLowerCase().includes(query.toLocaleLowerCase().trim()));
    return item ? `<div class="matched">${esc(item.name)} · ${money(item.amount)}</div>` : '';
  }
  function results(app) {
    const rows = filtered(app), shown = rows.slice(0,app.limit);
    if (!rows.length) return `<div class="empty"><h2>${app.query || app.merchant || app.month ? 'No receipts found.' : 'No receipts yet.'}</h2><p class="secondary">${app.query || app.merchant || app.month ? 'Try another item, store or SKU, or clear your filters.' : 'Import a receipt to start your collection.'}</p><button type="button" class="secondary-action" data-action="${app.query || app.merchant || app.month ? 'clear' : 'import'}">${app.query || app.merchant || app.month ? 'Clear search and filters' : 'Import a receipt'}</button></div>`;
    let prevMonth = '';
    let html = `<p class="result-count" aria-live="polite">${rows.length} ${rows.length===1?'receipt':'receipts'}${app.query ? ` matching “${esc(app.query)}”` : ''} · ${shown.length} shown</p>`;
    for (const r of shown) {
      const month = r.date.slice(0,7);
      if (prevMonth !== month) { if(prevMonth) html+='</div>'; html+=`<h2>${monthLabel(month)}</h2><div class="receipt-list">`; prevMonth=month; }
      const item = app.query.trim() ? r.items.find(i=>[i.name,i.raw,i.sku].join(' ').toLocaleLowerCase().includes(app.query.toLocaleLowerCase().trim())) : null;
      html+=`<button type="button" class="receipt-row" data-action="open" data-id="${r.id}" ${item ? `data-match="${esc(item.sku)}"` : ''} aria-label="Open ${esc(r.merchant)}, ${dateLabel(r.date)}, ${money(r.total)}, ${r.status}${item ? ', matching '+esc(item.name):''}"><span class="row-main"><strong>${esc(r.merchant)}</strong><span class="micro">${dateLabel(r.date)}${r.status!=='Saved'?' · Needs review':''}</span>${matchLabel(r,app.query)}</span><span class="amount">${money(r.total)} ›</span></button>`;
    }
    html+='</div>';
    if(rows.length>shown.length) html+=`<button type="button" class="secondary-action" data-action="more">Show next ${Math.min(25,rows.length-shown.length)} receipts</button>`;
    return html;
  }
  function library(app) {
    const months = [...new Set(app.receipts.map(r=>r.date.slice(0,7)))];
    return `<h1>${app.view==='search'?'Search':'All receipts'}</h1><label class="search-box">Items, stores or SKU<input type="search" class="search-input" placeholder="Search purchases" value="${esc(app.query)}" autocomplete="off"></label><div class="filters"><label>Store<select class="merchant-filter"><option value="">All stores</option>${merchantNames.map(m=>`<option ${app.merchant===m?'selected':''}>${esc(m)}</option>`).join('')}</select></label><label>Month<select class="month-filter"><option value="">All months</option>${months.map(m=>`<option value="${m}" ${app.month===m?'selected':''}>${monthLabel(m)}</option>`).join('')}</select></label></div><div class="results">${results(app)}</div>`;
  }
  function totals(receipt) { return `<div class="totals"><div class="total-row"><span>Subtotal</span><span class="amount">${money(sum(receipt))}</span></div><div class="total-row"><span>Discounts</span><span class="amount">${receipt.discount? '−'+money(receipt.discount):money(0)}</span></div><div class="total-row"><span>Tax</span><span class="amount">${money(receipt.tax)}</span></div><div class="total-row grand-total"><span>Total <span class="micro">CAD</span></span><span class="amount">${money(receipt.total)}</span></div></div>`; }
  function detail(app) {
    const r = selected(app);
    if (!r) return home(app);
    return `<div class="open-motion"><div class="receipt-sheet"><h1 class="merchant">${esc(r.merchant)}</h1><div class="receipt-meta">${dateLabel(r.date)} · ${r.items.length} items · CAD</div>${r.status!=='Saved'?`<div class="notice error"><strong>Needs review</strong><p>Item amounts do not match the recorded total. Check the original before splitting.</p></div>`:''}<h3>Items</h3>${r.items.map(i=>`<div class="receipt-line" ${app.focusItem===i.sku?'data-search-match="true"':''}><div class="line-text"><span>${esc(i.name)}</span><div class="micro">${esc(i.quantity)}${app.focusItem===i.sku?' · Search match':''}</div></div><span class="amount">${money(i.amount)}</span></div>`).join('')}${totals(r)}</div><button type="button" class="evidence-link" data-action="source"><span>Original receipt</span><span>View ›</span></button><p class="micro">${r.status==='Saved'?'Saved on this device.':'Saved · needs review.'} Corrections are kept separately from the original.</p></div>`;
  }
  function beginEdit(app,importing=false,manual=false) {
    app.importing = importing;
    app.editingOriginal = importing ? null : clone(selected(app));
    const source = importing ? makeReceipts(1)[0] : selected(app);
    app.draft = manual ? {id:'draft',merchant:'',date:'',items:[{name:'',raw:'',sku:'MAN001',quantity:'1',amount:0}],discount:0,tax:0,total:0,status:'Needs review',original:app.importSource || null} : clone(source);
    app.draft.id = importing ? 'draft' : source.id;
    if (importing && !manual) app.draft.items[0].name = 'Milk · check name';
    app.manual = manual;
    app.view='edit';
    app.error='';
    app.confirmed=!importing || manual;
    app.numericInvalid=new Set();
  }
  function edit(app) {
    const d = app.draft;
    return `<h1>${app.importing?app.manual?'Enter receipt':'Review receipt':'Edit receipt'}</h1><p class="secondary">${app.importing?'Check the details before saving.':'Changes update the digital receipt.'} The original stays separate.</p>${app.importing&&!app.manual?`<div class="notice"><strong>Check the item name</strong><p>Compare the highlighted milk line with the original. This is a review flag, not a confidence score.</p></div>`:''}<button type="button" class="evidence-link" data-action="source"><span>Original receipt</span><span>View ›</span></button><div class="field-grid"><label>Store<input data-field="merchant" value="${esc(d.merchant)}" autocomplete="off"></label><label>Purchase date<input type="date" data-field="date" value="${esc(d.date)}"></label></div><h2>Items</h2><div class="line-editors">${d.items.map((i,index)=>`<div class="line-editor"><label>Item ${index+1}<input data-item="${index}" data-field="name" value="${esc(i.name)}" autocomplete="off"></label><div class="edit-amount-row"><label>Quantity label<input data-item="${index}" data-field="quantity" value="${esc(i.quantity)}"></label><label>Line amount · CAD<input data-item="${index}" data-field="amount" value="${decimal(i.amount)}" inputmode="decimal" aria-label="Item ${index+1} line amount in CAD"></label></div><button type="button" class="plain-action" data-action="remove" data-item="${index}" aria-label="Remove item ${index+1}">Remove item</button></div>`).join('')}</div><button type="button" class="plain-action" data-action="add">＋ Add item</button><div class="field-grid"><label>Discounts · CAD<input data-field="discount" value="${decimal(d.discount)}" inputmode="decimal"></label><label>Tax · CAD<input data-field="tax" value="${decimal(d.tax)}" inputmode="decimal"></label><label>Recorded total · CAD<input data-field="total" value="${decimal(d.total)}" inputmode="decimal"></label></div>${app.importing&&!app.manual?'<label class="confirmation"><input type="checkbox" class="review-confirm" '+(app.confirmed?'checked':'')+'> I checked the flagged item against the original.</label>':''}<div class="reconcile" aria-live="polite">${reconcile(app)}</div><button type="button" class="primary save" data-action="save" ${canSave(app)?'':'disabled'}>Save receipt</button>`;
  }
  function validDraft(app) { const d=app.draft; return d.merchant.trim() && /^\d{4}-\d{2}-\d{2}$/.test(d.date) && d.items.length && d.items.every(i=>i.name.trim() && i.quantity.trim()) && app.numericInvalid.size===0 && expected(d)>=0; }
  function canSave(app) { return validDraft(app) && expected(app.draft)===app.draft.total && app.confirmed; }
  function reconcile(app) {
    const d = app.draft;
    const diff = d.total - expected(d);
    return `<strong>${money(sum(d))} in items</strong><p>${app.numericInvalid.size?'Enter amounts with up to two decimal places.':diff?`<span class="error-text">${money(Math.abs(diff))} difference. Check items, discounts, tax and the recorded total.</span>`:'Amounts match the recorded total.'}</p>${!validDraft(app)?'<p class="error-text">Complete the store, date and at least one named item with a quantity.</p>':''}${!app.confirmed?'<p>Confirm the flagged item before saving.</p>':''}`;
  }
  function source(app) {
    const r = app.sourceReturn==='edit' ? (app.draft.original || app.editingOriginal?.original || null) : ['error','processing'].includes(app.sourceReturn) ? app.importSource : selected(app)?.original;
    return `<h1>Original receipt</h1><p class="secondary">Synthetic source preview. This stands in for the imported image; it is not a real retailer receipt.</p>${r?`<div class="source-paper" role="img" aria-label="Synthetic original receipt transcription, unchanged by corrections">${esc(r.merchant)}\n${r.date}\n${r.items.map(i=>`${i.raw}\n${i.sku}    ${decimal(i.amount)}`).join('\n\n')}\n\nSUBTOTAL   ${decimal(sum(r))}\nDISCOUNT  -${decimal(r.discount)}\nTAX        ${decimal(r.tax)}\nTOTAL CAD  ${decimal(r.total)}\n\nSYNTHETIC · ${r.id}</div>`:'<div class="notice"><strong>No image attached</strong><p>Manual entry has no original image. An image can be attached during the later import workflow.</p></div>'}`;
  }
  function processing() { return `<div class="empty"><div class="empty-symbol">${icons.receipts}</div><h2>Reading receipt…</h2><p class="secondary">Looking for the store, items and amounts. You can leave this screen and return.</p><button type="button" class="secondary-action" data-action="manual">Enter manually</button><button type="button" class="plain-action" data-action="cancel-import">Cancel import</button></div>`; }
  function error() { return `<div class="empty"><h2>We couldn’t read<br>this receipt.</h2><p class="secondary">The image is still available. Try again, import a clearer image, or enter the details yourself.</p><div class="notice error" role="alert">No receipt has been saved.</div><button type="button" class="evidence-link" data-action="source"><span>Original receipt</span><span>View ›</span></button><button type="button" class="primary" data-action="retry">Try again</button><button type="button" class="secondary-action" data-action="manual">Enter manually</button><button type="button" class="plain-action" data-action="import">Import another image</button></div>`; }
  function render(app,keepScroll=false,focus=null) {
    const oldScroll=app.root.querySelector('.content')?.scrollTop || 0;
    const content = {home,library,search:library,detail,edit,source,processing,error}[app.view](app);
    app.root.innerHTML=`<div class="status-bar" aria-hidden="true"><span>9:41</span><span class="status-icons">••• ▰</span></div><div class="toolbar">${toolbar(app)}</div><div class="content">${content}</div>${tabbar(app)}<div class="announcement sr-only" role="status" aria-live="polite"></div>`;
    app.root.querySelector('.content').scrollTop = keepScroll?oldScroll:0;
    if(focus) app.root.querySelector(focus)?.focus({preventScroll:true});
    if(app.view==='detail' && app.focusItem) app.root.querySelector('[data-search-match]')?.scrollIntoView({block:'center',behavior:'instant'});
    syncOutcome();
  }
  function navigate(app,view) { app.view=view; if(view==='search') {app.query='';app.limit=25;} render(app,false,view==='search'?'.search-input':null); }
  function save(app) {
    if(!canSave(app)) return;
    const r=clone(app.draft);r.status='Saved';
    if(app.importing) { r.id=`I${app.receipts.length+1}`;r.original=r.original||null;app.receipts.unshift(r);app.empty=false; }
    else { app.receipts[app.receipts.findIndex(x=>x.id===r.id)] = r; }
    app.selected=r.id;app.view='detail';app.pending=false;app.draft=null;app.importing=false;app.confirmed=true;render(app);announce(app,'Receipt saved.');
  }
  function doAction(app,button) {
    const action=button.dataset.action;
    if(action==='navigate') return navigate(app,button.dataset.view);
    if(action==='open') {app.selected=button.dataset.id;app.returnView=app.view;app.focusItem=button.dataset.match||null;app.view='detail';render(app);app.root.querySelector('[data-action="back"]')?.focus({preventScroll:true});return;}
    if(action==='back') {
      if(app.view==='source') app.view=app.sourceReturn;
      else if(app.view==='edit') { app.view=app.importing?'home':'detail';app.pending=false;app.importing=false;app.draft=null; }
      else app.view=app.returnView;
      render(app);return;
    }
    if(action==='edit') {beginEdit(app);render(app);return;}
    if(action==='source') {app.sourceReturn=app.view;app.view='source';render(app);return;}
    if(action==='import' || action==='retry') {app.pending=true;app.importSource=makeReceipts(1)[0].original;app.returnView='home';app.view='processing';render(app);return;}
    if(action==='processing') {app.view='processing';render(app);return;}
    if(action==='cancel-import') {app.pending=false;app.view='home';render(app);announce(app,'Import cancelled.');return;}
    if(action==='manual') {app.pending=false;beginEdit(app,true,true);render(app);return;}
    if(action==='clear') {app.query='';app.merchant='';app.month='';app.limit=25;render(app);return;}
    if(action==='more') {app.limit+=25;render(app,true);announce(app,`${Math.min(app.limit,filtered(app).length)} receipts shown.`);return;}
    if(action==='add') {app.draft.items.push({name:'',raw:'',sku:`MAN${app.draft.items.length+1}`,quantity:'1',amount:0});render(app,true);app.root.querySelector('.line-editor:last-child input')?.focus();return;}
    if(action==='remove') {app.draft.items.splice(Number(button.dataset.item),1);app.numericInvalid.clear();render(app,true);announce(app,'Item removed.');return;}
    if(action==='save') save(app);
  }
  function updateDraft(app,input) {
    const field=input.dataset.field,key=`${input.dataset.item ?? 'receipt'}-${field}`;
    const target=input.dataset.item!==undefined?app.draft.items[Number(input.dataset.item)]:app.draft;
    if(['amount','discount','tax','total'].includes(field)) {const parsed=cents(input.value);if(parsed===null)app.numericInvalid.add(key);else {app.numericInvalid.delete(key);target[field]=parsed;}}
    else target[field]=input.value;
    app.root.querySelector('.reconcile').innerHTML=reconcile(app);
    app.root.querySelector('.save').disabled=!canSave(app);
  }
  function motionReduced() { return settings.reduce || window.matchMedia('(prefers-reduced-motion: reduce)').matches; }
  for (const app of apps) {
    let drag=null,suppressClick=false;
    app.root.addEventListener('click',event=>{const button=event.target.closest('button[data-action]');if(!button)return;if(suppressClick){suppressClick=false;return;}doAction(app,button);});
    app.root.addEventListener('input',event=>{
      const input=event.target;
      if(input.matches('.search-input')) {app.query=input.value;app.limit=25;app.root.querySelector('.results').innerHTML=results(app);}
      if(input.matches('[data-field]'))updateDraft(app,input);
    });
    app.root.addEventListener('change',event=>{
      const input=event.target;
      if(input.matches('.merchant-filter')) {app.merchant=input.value;app.limit=25;app.root.querySelector('.results').innerHTML=results(app);}
      if(input.matches('.month-filter')) {app.month=input.value;app.limit=25;app.root.querySelector('.results').innerHTML=results(app);}
      if(input.matches('.review-confirm')) {app.confirmed=input.checked;app.root.querySelector('.reconcile').innerHTML=reconcile(app);app.root.querySelector('.save').disabled=!canSave(app);}
    });
    app.root.addEventListener('pointerdown',event=>{const slip=event.target.closest('.slip');if(!slip || settings.scale>=1.5 || motionReduced() || event.button!==0)return;drag={slip,y:event.clientY,x:event.clientX,pointer:event.pointerId,moved:false};slip.setPointerCapture(event.pointerId);});
    app.root.addEventListener('pointermove',event=>{if(!drag)return;const dy=Math.max(-110,Math.min(0,event.clientY-drag.y));drag.moved=Math.abs(dy)>8;drag.slip.style.transform=`translateY(${dy*.55}px)${app.id==='paper'?' rotate('+(-dy/90)+'deg)':''}`;});
    app.root.addEventListener('pointerup',event=>{if(!drag)return;const current=drag;drag=null;current.slip.style.transform='';if(current.y-event.clientY>=64 && Math.abs(event.clientX-current.x)<80){suppressClick=true;doAction(app,current.slip);setTimeout(()=>{suppressClick=false;},0);}else if(current.moved){suppressClick=true;setTimeout(()=>{suppressClick=false;},0);}});
    app.root.addEventListener('pointercancel',()=>{if(drag)drag.slip.style.transform='';drag=null;});
  }
  function syncOutcome() {document.getElementById('outcome-controls').hidden=!apps.some(a=>a.pending);}
  function applySettings() {
    const sizes={small:[320,690],regular:[393,852],large:[430,932]};
    for(const app of apps) {app.root.style.setProperty('--phone-width',`${sizes[settings.size][0]}px`);app.root.style.setProperty('--phone-height',`${sizes[settings.size][1]}px`);app.root.style.setProperty('--scale',settings.scale);app.root.classList.toggle('large-text',settings.scale>=1.5);app.root.classList.toggle('reduce',motionReduced());app.root.classList.toggle('dark',settings.appearance==='dark');app.root.classList.toggle('light',settings.appearance==='light');app.root.closest('.concept').style.setProperty('--phone-width',`${sizes[settings.size][0]}px`);render(app);}
  }
  function scenario(value) {
    for(const app of apps) {
      app.empty=false;app.pending=false;app.importing=false;app.draft=null;app.selected=app.receipts[0]?.id;app.query='';app.merchant='';app.month='';app.limit=25;app.returnView='home';app.focusItem=null;
      if(value==='empty') {app.empty=true;app.view='home';}
      else if(value==='search' || value==='nomatch') {app.query=value==='search'?'milk':'zzzz';app.view='search';}
      else if(value==='processing') {app.pending=true;app.importSource=makeReceipts(1)[0].original;app.view='processing';}
      else if(value==='review') beginEdit(app,true);
      else if(value==='edit') beginEdit(app);
      else {app.view=value;if(value==='error')app.importSource=makeReceipts(1)[0].original;}
      render(app);
    }
  }
  document.getElementById('collection').addEventListener('change',event=>{settings.count=Number(event.target.value);for(const app of apps)app.receipts=makeReceipts(settings.count);scenario(document.getElementById('scenario').value);});
  document.getElementById('screen-size').addEventListener('change',event=>{settings.size=event.target.value;applySettings();});
  document.getElementById('text-size').addEventListener('change',event=>{settings.scale=Number(event.target.value);applySettings();});
  document.getElementById('reduce-motion').addEventListener('change',event=>{settings.reduce=event.target.checked;applySettings();});
  document.getElementById('appearance').addEventListener('change',event=>{settings.appearance=event.target.value;applySettings();});
  document.getElementById('scenario').addEventListener('change',event=>scenario(event.target.value));
  document.getElementById('finish-reading').addEventListener('click',()=>{const outcome=document.getElementById('import-outcome').value;for(const app of apps.filter(a=>a.pending)){app.pending=false;if(outcome==='review')beginEdit(app,true);else app.view='error';render(app);}});
  window.matchMedia('(prefers-reduced-motion: reduce)').addEventListener('change',()=>applySettings());
  applySettings();
  // Only synthetic state is exposed for reproducible review checks.
  window.RcpLensDesign = {getReceipts:count=>makeReceipts(count),parseCents:cents,expectedTotal:expected,snapshot:()=>apps.map(a=>({concept:a.id,view:a.view,count:a.receipts.length,query:a.query,merchant:a.merchant,month:a.month,pending:a.pending}))};
})();
