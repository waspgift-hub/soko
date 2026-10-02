// Reconciles firestore.indexes.json against the indexes actually deployed in
// the production project.
//
// Why this exists: `firebase deploy --only firestore:indexes` treats the file as
// the desired state. Two indexes were live in production but absent from the
// file, so a deploy risked pruning an index that live queries depend on. This
// script adds any deployed-but-undeclared index back into the file so the
// repository and the project agree.
//
// Read-only against the deployed project; it never deletes anything.
//
//   node tools/reconcile-firestore-indexes.js --project sokonimoko-8c171-a8d14
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const file = path.join(__dirname, '..', 'firestore.indexes.json');
const json = JSON.parse(fs.readFileSync(file, 'utf8'));

// Firestore stores every index with an implicit `__name__` tiebreaker appended
// and normalises the direction, so a raw comparison reports every index as
// different. Compare on the declared fields only.
const norm = (i) =>
  `${i.collectionGroup}|${(i.fields || [])
    .filter((f) => f.fieldPath !== '__name__')
    .map((f) => `${f.fieldPath}:${f.order || f.arrayConfig || ''}`)
    .join(',')}`;

const argv = process.argv.slice(2);
const projectArg = argv.indexOf('--project');
const project = projectArg >= 0 ? argv[projectArg + 1] : null;
if (!project) {
  console.error('usage: node tools/reconcile-firestore-indexes.js --project <projectId>');
  process.exit(1);
}

const raw = execFileSync('firebase', ['firestore:indexes', '--project', project, '--json'], {
  encoding: 'utf8',
  maxBuffer: 32 * 1024 * 1024,
  shell: true,
});
const parsed = JSON.parse(raw.replace(/^\uFEFF/, ''));
const deployed = (parsed.result && parsed.result.indexes) || parsed.indexes || [];

const declared = new Set((json.indexes || []).map(norm));
const missingFromFile = deployed.filter((i) => !declared.has(norm(i)));

if (missingFromFile.length === 0) {
  console.log(`in sync: all ${deployed.length} deployed indexes are declared in the file`);
  process.exit(0);
}

const added = [];
for (const i of missingFromFile) {
  json.indexes.push({
    collectionGroup: i.collectionGroup,
    queryScope: i.queryScope,
    fields: i.fields
      .filter((f) => f.fieldPath !== '__name__')
      .map((f) => (f.arrayConfig ? { fieldPath: f.fieldPath, arrayConfig: f.arrayConfig } : { fieldPath: f.fieldPath, order: f.order })),
  });
  added.push(norm(i));
}

// Appended, not re-sorted: reordering the whole file would bury a two-line
// reconciliation under a several-hundred-line diff.
fs.writeFileSync(file, `${JSON.stringify(json, null, 2)}\n`);
console.log(`added ${added.length} deployed-but-undeclared index(es) to firestore.indexes.json:`);
added.forEach((a) => console.log(`  + ${a}`));