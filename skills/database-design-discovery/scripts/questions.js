#!/usr/bin/env node
/* List the questions an interviewer should ask next.
   Usage:
     node scripts/questions.js                       # every unconditional question, grouped by section
     node scripts/questions.js --answers a.json      # only questions VISIBLE given these answers (branches open up)
     node scripts/questions.js --answers a.json --unanswered   # …and not yet answered
     node scripts/questions.js --section A,B         # restrict to sections
     node scripts/questions.js --format json         # machine-readable
   Answer codes are what you record in answers.json. Every question also accepts
   "__other" plus free text in the "other" map.
*/
const fs = require('fs');
const path = require('path');
const E = require(path.join(__dirname, 'engine.js'));

const args = process.argv.slice(2);
const opt = (k, d) => { const i = args.indexOf(k); return i >= 0 ? args[i + 1] : d; };
const flag = k => args.includes(k);

let A = {}, other = {};
if (opt('--answers')) ({ answers: A, other } = E.loadAnswers(JSON.parse(fs.readFileSync(opt('--answers'), 'utf8'))));
const sections = opt('--section') ? opt('--section').split(',').map(s => s.trim().toUpperCase()) : null;
const onlyUnanswered = flag('--unanswered');

let qs = E.visibleQuestions(A);
if (sections) qs = qs.filter(q => sections.includes(q.s));
if (onlyUnanswered) qs = qs.filter(q => !E.isAnswered(q, A, other));

if (opt('--format') === 'json') {
  process.stdout.write(JSON.stringify(qs.map(q => ({
    id: q.id, section: q.s, type: q.type === 'many' ? 'multi' : 'single', required: !!q.req,
    question: q.t, help: E.strip(q.help || ''),
    options: q.opts.map(o => ({ code: o.v, label: o.l, note: E.strip(o.s || '') })).concat([{ code: '__other', label: 'Other — specify', note: 'Record free text in the "other" map.' }]),
    answered: E.isAnswered(q, A, other), current: A[q.id] ?? null,
  })), null, 2) + '\n');
  process.exit(0);
}

let cur = null;
for (const q of qs) {
  if (q.s !== cur) {
    cur = q.s;
    const s = E.SECTIONS.find(x => x.id === cur);
    console.log(`\n## Section ${cur} — ${s.name}\n${s.lede}\n`);
  }
  const tag = q.type === 'many' ? ' [select all that apply]' : '';
  const done = E.isAnswered(q, A, other) ? `  (answered: ${JSON.stringify(A[q.id])})` : '';
  console.log(`### ${q.id}. ${q.t}${tag}${done}`);
  if (q.help) console.log(`> ${E.strip(q.help)}`);
  for (const o of q.opts) console.log(`- \`${o.v}\` — ${o.l}${o.s ? ` _(${E.strip(o.s)})_` : ''}`);
  console.log('- `__other` — Other: describe it (goes in the "other" map, verbatim)\n');
}
const total = E.visibleQuestions(A).length, answered = E.visibleQuestions(A).filter(q => E.isAnswered(q, A, other)).length;
console.error(`[${qs.length} questions listed · ${answered}/${total} visible questions answered]`);
