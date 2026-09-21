const fs = require('fs');
const p = 'C:/Users/user/Desktop/SOKO VIBE/ttr/soko_langu/server/src/modules/kyc/routes.js';
const t = fs.readFileSync(p, 'utf8');
const lines = t.split(/\r?\n/);
const pats = [
  ["send-phone", /router\.post\('\/verify\/phone\/send'/],
  ["confirm-phone", /router\.post\('\/verify\/phone\/confirm'/],
  ["send-email", /router\.post\('\/verify\/email\/send'/],
  ["confirm-email", /router\.post\('\/verify\/email\/confirm'/],
  ["status", /router\.get\('\/status\/'/],
  ["submit", /router\.post\('\/submit'/],
];
for (const [name, re] of pats) {
  const hits = [];
  lines.forEach((l, i) => { if (re.test(l)) hits.push(i + 1); });
  console.log(name.padEnd(16), '=>', hits.join(', ') || 'NONE');
}
