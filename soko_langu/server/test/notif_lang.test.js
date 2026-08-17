const test = require('node:test');
const assert = require('node:assert/strict');

const { localizeNotif, localizeSms, localizeDefaultReason } = require('../notif_lang');

// ---------------------------------------------------------------------------
// localizeSms — one SMS is ONE language (sw / en / zh, no mixing)
// ---------------------------------------------------------------------------

test('localizeSms: sw stays Swahili', () => {
  const msg = 'OTP yako ni 123456. Inaisha kwa dakika 10.';
  assert.equal(localizeSms('sw', msg), msg);
});

test('localizeSms: OTP to English', () => {
  const msg = 'OTP yako ni 123456. Inaisha kwa dakika 10.';
  const out = localizeSms('en', msg);
  assert.equal(out, 'Your OTP is 123456. It expires in 10 minutes.');
  assert.ok(!/[À-ũ]/.test(out), 'no Swahili tokens remain');
});

test('localizeSms: OTP to Chinese', () => {
  const msg = 'OTP yako ni 123456. Inaisha kwa dakika 10.';
  const out = localizeSms('zh', msg);
  assert.equal(out, '您的验证码是 123456，10分钟内有效。');
});

test('localizeSms: buyer escrow hold to English', () => {
  const msg = 'Malipo ya TZS 50,000 kwa Oda #ORD9 yamepokelewa na kuwekwa salama Escrow. Muuzaji anajiandaa kutuma mzigo wako.';
  const out = localizeSms('en', msg);
  assert.ok(out.includes('safely held in escrow'), out);
  assert.ok(out.includes('#ORD9'), out);
});

test('localizeSms: buyer escrow hold to Chinese', () => {
  const msg = 'Malipo ya TZS 50,000 kwa Oda #ORD9 yamepokelewa na kuwekwa salama Escrow. Muuzaji anajiandaa kutuma mzigo wako.';
  const out = localizeSms('zh', msg);
  assert.ok(out.includes('订单 #ORD9'), out);
  assert.ok(out.includes('TZS 50,000'), out);
});

test('localizeSms: seller paid to English', () => {
  const msg = 'Oda #ORD9 imelipiwa! Fedha ipo salama Escrow. Tafadhali kamilisha usafirishaji stendi na ujaze risiti ya basi kwenye app.';
  const out = localizeSms('en', msg);
  assert.ok(out.includes('Order #ORD9 has been paid'), out);
});

test('localizeSms: dispatched to Chinese', () => {
  const msg = 'Mzigo wa Oda #ORD9 umesafirishwa kupitia basi la AB (T123). Fungua app kuona risiti yako ya kidijitali.';
  const out = localizeSms('zh', msg);
  assert.ok(out.includes('巴士 AB'), out);
  assert.ok(out.includes('#ORD9'), out);
});

test('localizeSms: delivered to English', () => {
  const msg = 'Mteja amethibitisha kupokea mzigo #ORD9. TZS 47,000 zimetolewa Escrow na kuwekwa kwenye pochi yako.';
  const out = localizeSms('en', msg);
  assert.ok(out.includes('confirmed receiving shipment #ORD9'), out);
});

test('localizeSms: payment failed to Chinese', () => {
  const msg = 'Malipo ya Bidhaa hayakukamilika. Tafadhali fungua app na ujaribu tena.';
  const out = localizeSms('zh', msg);
  assert.ok(out.includes('付款未完成'), out);
});

test('localizeSms: refund to English', () => {
  const msg = 'Fedha za Bidhaa (Oda #ORD9) zimerudishwa kwenye akaunti yako.';
  const out = localizeSms('en', msg);
  assert.ok(out.includes('funds for'), out);
});

test('localizeSms: boost success to Chinese', () => {
  const msg = 'Malipo ya Boost ya TZS 3,000 yamefanikiwa! Bidhaa yako sasa inaonyeshwa kipaumbele hadi 22/8/2026.';
  const out = localizeSms('zh', msg);
  assert.ok(out.includes('推广付款 TZS 3,000'), out);
});

test('localizeSms: deposit fail to English', () => {
  const msg = 'Malipo ya TZS 10,000 hayakukamilika. Sababu: Sali AB1. Jaribu tena kwenye app.';
  const out = localizeSms('en', msg);
  assert.ok(out.includes('because Sali AB1'), out);
  assert.ok(!out.includes('Sababu'), 'no "Sababu" in English output');
});

test('localizeSms: deposit fail to Chinese', () => {
  const msg = 'Malipo ya TZS 10,000 hayakukamilika. Sababu: Sali AB1. Jaribu tena kwenye app.';
  const out = localizeSms('zh', msg);
  assert.ok(out.includes('因为Sali AB1'), out);
  assert.ok(!out.includes('Sababu'), 'no "Sababu" in Chinese output');
});

test('localizeSms: payment fail to English uses because', () => {
  const msg = 'Malipo ya Bidhaa hayakukamilika. Tafadhali jaribu tena kwenye app. Sababu: payment failed';
  const out = localizeSms('en', msg);
  assert.ok(out.includes('because payment failed'), out);
  assert.ok(!/Sababu|原因/.test(out), 'no Sababu/原因 in English output');
});

test('localizeSms: boost fail to Chinese uses because', () => {
  const msg = 'Malipo ya Boost ya TZS 3,000 hayakukamilika. Sababu: malipo yameshindikana. Jaribu tena kwenye app.';
  const out = localizeSms('zh', msg);
  assert.ok(out.includes('因为malipo yameshindikana'), out);
  assert.ok(!out.includes('Sababu'), 'no "Sababu" in Chinese output');
});

test('localizeSms: promo broadcast to Chinese', () => {
  const msg = 'Tangaza bidhaa zako kwa bei nafuu na wanunue zaidi! Sambaza neno kwa marafiki na familia. Kila agizo linalolipwa linakusaidia kukua. Pakia Soko Vibe leo!';
  const out = localizeSms('zh', msg);
  assert.ok(out.includes('推广您的商品'), out);
  assert.ok(/[À-ũ]/.test(out) === false, 'no Swahili tokens remain');
});

test('localizeSms: promo broadcast to English', () => {
  const msg = 'Tangaza bidhaa zako kwa bei nafuu na wanunue zaidi! Sambaza neno kwa marafiki na familia. Kila agizo linalolipwa linakusaidia kukua. Pakia Soko Vibe leo!';
  const out = localizeSms('en', msg);
  assert.ok(out.includes('Advertise your products'), out);
});

test('localizeSms: unknown template keeps single (Swahili) language', () => {
  const msg = 'Ujumbe wa kipekee usiorahisishwa.';
  assert.equal(localizeSms('zh', msg), msg);
});

// ---------------------------------------------------------------------------
// localizeNotif — notices are single (Swahili, English, or Chinese)
// ---------------------------------------------------------------------------

test('localizeNotif: sw stays untouched', () => {
  const { title, body } = localizeNotif('sw', 'Malipo Yamekamilika!', 'Malipo ya X yamepokelewa.');
  assert.equal(title, 'Malipo Yamekamilika!');
  assert.equal(body, 'Malipo ya X yamepokelewa.');
});

test('localizeNotif: title exact match to Chinese', () => {
  const { title } = localizeNotif('zh', 'Malipo Yamekamilika!', 'Malipo ya X yamepokelewa.');
  assert.equal(title, '付款已完成！');
});

test('localizeNotif: dynamic title to English', () => {
  const { title } = localizeNotif('en', 'Onyo 2/3 — Sera ya Soko Vibe', 'Unaonywa (2/3): Ulaghai. Ukiingia makosa 3, akaunti itasimamishwa kabisa.');
  assert.equal(title, 'Warning 2/3 — Soko Vibe Policy');
});

test('localizeNotif: dynamic title to Chinese', () => {
  const { title } = localizeNotif('zh', 'Bidhaa Mpya katika Mifuko!', 'abc');
  assert.equal(title, 'Mifuko的新品！');
});

test('localizeNotif: current listener template to English (escrow hold)', () => {
  const { title, body } = localizeNotif('en', 'Malipo Yamekamilika!', 'Malipo ya Kisenge chenye chawa yamepokelewa na kuwekwa escrow salama.');
  assert.equal(title, 'Payment Completed!');
  assert.ok(body.includes('safely placed in escrow'), body);
});

test('localizeNotif: unmatched body keeps original single language', () => {
  const { body } = localizeNotif('en', 'T', 'Ujumbe wa kipekee usiorahisishwa.');
  assert.equal(body, 'Ujumbe wa kipekee usiorahisishwa.');
});

test('localizeNotif: payout in-app variant to English', () => {
  const { body } = localizeNotif('en', 'Pesa Zimetumwa Moja kwa Moja!', 'Bidhaa — TZS 45,500 zimetumwa kwa simu yako. Fee ya TZS 4,500 imekatwa.');
  assert.ok(body.includes('A fee of TZS 4,500 was deducted'), body);
});

test('localizeNotif: payout in-app variant to Chinese', () => {
  const { body } = localizeNotif('zh', 'Pesa Zimetumwa Moja kwa Moja!', 'Bidhaa — TZS 45,500 zimetumwa kwa simu yako. Fee ya TZS 4,500 imekatwa.');
  assert.ok(body.includes('已扣除 TZS 4,500'), body);
});

test('localizeNotif: admin dispute with empty note to English', () => {
  const { body } = localizeNotif('en', '⚖️ Uamuzi wa Mgogoro', 'Admin ameamua pesa zitolewe kwa muuzaji. ');
  assert.equal(body, 'The admin ruled that the money be released to the seller.');
});

test('localizeNotif: admin dispute with note to Chinese', () => {
  const { body } = localizeNotif('zh', '⚖️ Uamuzi wa Mgogoro', 'Admin ameamua pesa zitolewe kwa muuzaji. Tumeamua kuwa muuzaji ni sahihi.');
  assert.ok(body.includes('管理员裁定款项将释放给卖家。Tumeamua kuwa muuzaji ni sahihi.'), body);
});

test('localizeNotif: admin released-to-you with no note to English', () => {
  const { body } = localizeNotif('en', '⚖️ Uamuzi wa Mgogoro', 'Admin ameamua pesa zikutolee. ');
  assert.equal(body, 'The admin ruled that the money be released to you.');
});

// ---------------------------------------------------------------------------
// localizeDefaultReason — gateway default causes are single-language too
// ---------------------------------------------------------------------------

test('localizeDefaultReason: sw default stays Swahili', () => {
  assert.equal(localizeDefaultReason('sw', 'Payment failed'), 'Payment failed');
  assert.equal(localizeDefaultReason('sw', 'Nyingine'), 'Nyingine');
});

test('localizeDefaultReason: en default stays English', () => {
  assert.equal(localizeDefaultReason('en', 'Payment failed'), 'Payment failed');
  assert.equal(localizeDefaultReason('en', 'payment failed'), 'payment failed');
});

test('localizeDefaultReason: zh default is Chinese', () => {
  assert.equal(localizeDefaultReason('zh', 'Payment failed'), '付款失败');
  assert.equal(localizeDefaultReason('zh', 'payment failed'), '付款失败');
});

test('localizeDefaultReason: unknown provider reason untouched', () => {
  assert.equal(localizeDefaultReason('zh', 'Sali AB1'), 'Sali AB1');
});