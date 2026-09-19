#!/usr/bin/env node
/* Turn an answers file into the design brief.
   Usage:
     node scripts/recommend.js answers.json                 # Markdown brief to stdout
     node scripts/recommend.js answers.json --format json   # {recs, flags, checks, answers}
     node scripts/recommend.js answers.json --out brief.md
     node scripts/recommend.js answers.json --allow-partial # run even if questions are unanswered (flagged in output)
   Deterministic: the same answers always produce the same brief. Every
   recommendation carries the answers that drove it and its source; a line
   with no source is printed as unsupported.
*/
const fs = require('fs');
const path = require('path');
const E = require(path.join(__dirname, 'engine.js'));

const args = process.argv.slice(2);
const file = args.find(a => !a.startsWith('--'));
const opt = (k, d) => { const i = args.indexOf(k); return i >= 0 ? args[i + 1] : d; };
if (!file) { console.error('usage: node scripts/recommend.js answers.json [--format md|json] [--out file] [--allow-partial]'); process.exit(2); }

const { answers: A, other, notes } = E.loadAnswers(JSON.parse(fs.readFileSync(file, 'utf8')));
const vis = E.visibleQuestions(A);
const missing = vis.filter(q => q.req && !E.isAnswered(q, A, other));
if (missing.length && !args.includes('--allow-partial')) {
  console.error(`${missing.length} visible required question(s) unanswered: ${missing.map(q => q.id).join(', ')}\nRun scripts/check-answers.js, or pass --allow-partial to proceed anyway (the brief will say so).`);
  process.exit(1);
}
const out = E.recommend(A);
const S = E.strip;
const labelFor = (q, v) => v === E.OTHER ? `Other — ${other[q.id] || '(not described)'}` : (q.opts.find(o => o.v === v) || { l: v }).l;
const answerText = q => { const v = A[q.id]; if (v == null || (Array.isArray(v) && !v.length)) return '—'; return (Array.isArray(v) ? v : [v]).map(x => labelFor(q, x)).join('; '); };

if (opt('--format') === 'json') {
  const j = { generated_at: new Date().toISOString(), questions_visible: vis.length, questions_missing: missing.map(q => q.id),
    flags: out.flags.map(f => ({ severity: f.sev, title: S(f.title), why: S(f.body), fix: S(f.fix) })),
    recommendations: out.recs.map(r => ({ area: r.area, primary: { name: S(r.p.n), detail: S(r.p.d || '') }, alternative: { name: S(r.a.n), detail: S(r.a.d || '') }, switch_when: S(r.t), why: r.why.map(S), sources: (r.cite || []).map(S) })),
    schema_checklist: out.checks.map(c => ({ group: c.g, item: S(c.m), detail: S(c.d) })),
    answers: vis.map(q => ({ id: q.id, question: q.t, answer: answerText(q), codes: A[q.id] ?? null, other: other[q.id] || null, note: notes[q.id] || null })) };
  const text = JSON.stringify(j, null, 2);
  opt('--out') ? fs.writeFileSync(opt('--out'), text) : process.stdout.write(text + '\n');
  process.exit(0);
}

const L = [];
L.push('# Database design brief', '', `Generated ${new Date().toISOString().slice(0, 10)} from ${vis.length} answered questions by ${out.recs.length} rules. Every recommendation lists the answers that drove it and its source; challenge any line without one.`, '');
if (missing.length) L.push(`> **Partial run.** ${missing.length} visible question(s) were unanswered: ${missing.map(q => q.id).join(', ')}. Rules that depend on them may be wrong.`, '');
L.push('## 1. Conflicts and risks in the answers', '');
if (!out.flags.length) L.push('No conflicts. That is the intended state and it is rare on a first pass.', '');
for (const sev of ['bad', 'warn', 'info']) for (const f of out.flags.filter(x => x.sev === sev)) {
  L.push(`### [${{ bad: 'CONTRADICTION', warn: 'RISK', info: 'CONSIDER' }[sev]}] ${S(f.title)}`, '', S(f.body), '', `**What to do:** ${S(f.fix)}`, '');
}
L.push('## 2. Recommended stack', '', 'Primary, alternative, and the condition that should make you switch.', '');
out.recs.forEach((r, i) => {
  L.push(`### 2.${i + 1} ${r.area}`, '');
  L.push(`- **Primary:** ${S(r.p.n)}${r.p.d ? ` — ${S(r.p.d)}` : ''}`);
  L.push(`- **Alternative:** ${S(r.a.n)}${r.a.d ? ` — ${S(r.a.d)}` : ''}`);
  L.push(`- **Switch when:** ${S(r.t)}`, '', '**Why, from the answers:**', '');
  r.why.forEach(w => L.push(`- ${S(w)}`));
  L.push('');
  if (r.cite && r.cite.length) r.cite.forEach(c => L.push(`> Source: ${S(c)}`));
  else L.push('> **No source recorded — treat this recommendation as unsupported.**');
  L.push('');
});
L.push('## 3. What the schema must contain', '', 'Each item exists because an answer requires it. Map each to a part of `assets/reference-schema.sql` via `references/schema-guide.md`.', '');
const groups = { identity: 'Identity and accounts', authz: 'Roles and permissions', org: 'Organisation structure', privacy: 'Privacy and consent', audit: 'Audit and evidence', tenancy: 'Tenancy' };
for (const [g, name] of Object.entries(groups)) { const items = out.checks.filter(c => c.g === g); if (!items.length) continue; L.push(`### ${name}`, ''); items.forEach(c => L.push(`- [ ] **${S(c.m)}** — ${S(c.d)}`)); L.push(''); }
L.push('## 4. Answers (the audit trail for this design)', '', '| # | Question | Answer | Note |', '|---|---|---|---|');
vis.forEach(q => L.push(`| ${q.id} | ${q.t.replace(/\|/g, '/')} | ${answerText(q).replace(/\|/g, '/')} | ${(notes[q.id] || '').replace(/\|/g, '/').replace(/\n/g, ' ')} |`));
L.push('');
const text = L.join('\n');
opt('--out') ? fs.writeFileSync(opt('--out'), text) : process.stdout.write(text);
