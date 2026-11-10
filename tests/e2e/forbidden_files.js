// Fails if internal/dev files sit in the served set (repo root, outside the allowed non-served dirs).
const { execSync } = require('child_process');
const ALLOWED_DIRS = ['internal/', 'docs/', 'design/', 'security/', 'tests/', '.github/'];
const BAD = [/\.sql$/i, /\.md$/i, /(^|\/)setup-[^/]*\.html$/i, /(^|\/)audit-[^/]*\.html$/i];
const root = require('path').resolve(__dirname, '..', '..');
// tracked + untracked-not-ignored files
const files = execSync('git ls-files -co --exclude-standard', { cwd: root, encoding: 'utf8' }).split('\n').filter(Boolean);
const offenders = files.filter(f => !ALLOWED_DIRS.some(d => f.startsWith(d)) && BAD.some(r => r.test(f)));
if (offenders.length) { console.error('FAIL forbidden files in served set:\n  ' + offenders.join('\n  ')); process.exit(1); }
console.log('PASS forbidden_files: none of ' + files.length + ' files are .sql/.md/setup-*/audit-* outside ' + ALLOWED_DIRS.join(' '));
