#!/usr/bin/env node
/* Validate an answers file before generating a recommendation.
   Usage: node scripts/check-answers.js answers.json
   Exit 0 = complete; exit 1 = incomplete or has unknown codes (details on stdout).
   Prints, in order: unknown question ids / answer codes, then every visible
   required question that is still unanswered (with its section), then a summary.
*/
const fs = require('fs');
const path = require('path');
const E = require(path.join(__dirname, 'engine.js'));
const file = process.argv[2];
if (!file) { console.error('usage: node scripts/check-answers.js answers.json'); process.exit(2); }
const { answers: A, other } = E.loadAnswers(JSON.parse(fs.readFileSync(file, 'utf8')));

const bad = E.unknownCodes(A);
const vis = E.visibleQuestions(A);
const missing = vis.filter(q => q.req && !E.isAnswered(q, A, other));
const otherNeedsText = vis.filter(q => { const v = A[q.id]; return (Array.isArray(v) ? v.includes(E.OTHER) : v === E.OTHER) && !(other[q.id] || '').trim(); });

if (bad.length) { console.log('UNKNOWN CODES'); bad.forEach(b => console.log(`  ${b.id}: ${b.code ?? ''} — ${b.reason}`)); }
if (otherNeedsText.length) { console.log('OTHER SELECTED WITHOUT TEXT'); otherNeedsText.forEach(q => console.log(`  ${q.id}`)); }
if (missing.length) {
  console.log('UNANSWERED (visible, required)');
  missing.forEach(q => console.log(`  ${q.id}  [${q.s}]  ${q.t}`));
}
console.log(`\n${vis.length - missing.length}/${vis.length} visible questions answered · ${missing.length} missing · ${bad.length} unknown codes`);
process.exit((bad.length || missing.length || otherNeedsText.length) ? 1 : 0);
