// Runs the Godot project from the command line with the Harness autoload,
// collects PERF/STATE/SHOT lines and errors. Mirrors the web build's game-smoke.
//   node tools/godot-run.mjs --seconds 10 --script "throttle:5,steer_right:2,throttle:3" --tag demo [--scene res://scenes/X.tscn] [--every 2] [--extra "--world=storm"]
// --extra passes extra user args (space separated) through to the scene after the harness args.
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const args = process.argv.slice(2);
const getArg = (n, d) => { const i = args.indexOf(`--${n}`); return i >= 0 ? args[i + 1] : d; };
const godot = process.env.GODOT || 'C:/dev/games/godot/Godot_v4.7.2-stable_win64_console.exe';
const proj = path.resolve(import.meta.dirname, '..');
const tag = getArg('tag', 'run');
const shots = path.resolve(proj, 'tools/shots', tag).replace(/\\/g, '/');
fs.rmSync(shots, { recursive: true, force: true });
fs.mkdirSync(shots, { recursive: true });
const seconds = getArg('seconds', '10');
const gargs = ['--path', proj, '--windowed', '--disable-vsync', '--resolution', getArg('res', '1280x720')];
if (getArg('gpu')) gargs.push('--gpu-index', getArg('gpu'));   // 0 = default (RTX here), 1 = Intel UHD
if (getArg('scene')) gargs.push(getArg('scene'));
gargs.push('--', `--shots=${shots}`, `--seconds=${seconds}`, `--script=${getArg('script', 'throttle:5,steer_right:2,throttle:3')}`, '--perf');
if (getArg('extra')) gargs.push(...getArg('extra').split(' ').filter(Boolean));   // pass-through user args, e.g. --extra "--skip=lagoon"
if (getArg('every')) gargs.push(`--every=${getArg('every')}`);
if (getArg('extra')) gargs.push(...getArg('extra').split(/\s+/).filter(Boolean));
console.log('>', path.basename(godot), gargs.join(' '));
const t0 = Date.now();
const r = spawnSync(godot, gargs, { encoding: 'utf8', timeout: (parseFloat(seconds) + 120) * 1000, maxBuffer: 64 * 1024 * 1024 });
const out = (r.stdout || '') + (r.stderr || '');
const lines = out.split(/\r?\n/);
const perf = lines.filter(l => l.startsWith('PERF'));
const errors = lines.filter(l => /^(ERROR|SCRIPT ERROR|USER ERROR)/.test(l));
const warnings = lines.filter(l => /^(WARNING|USER WARNING)/.test(l));
console.log(perf.join('\n'));
console.log(lines.filter(l => l.startsWith('STATE')).slice(-2).join('\n'));
console.log(lines.filter(l => l.startsWith('SHOT')).map(l => '  ' + l).join('\n'));
const fps = perf.map(l => +(/fps=(\d+)/.exec(l)?.[1] || 0)).filter(Boolean).slice(2).sort((a, b) => a - b);
if (fps.length) console.log(`> steady fps: median ${fps[fps.length >> 1]}, min ${fps[0]}  (${((Date.now() - t0) / 1000).toFixed(1)}s wall)`);
if (errors.length) { console.log(`\n--- ${errors.length} error lines (unique, first 12) ---`); for (const e of [...new Set(errors)].slice(0, 12)) console.log(e); }
if (warnings.length) console.log(`--- ${warnings.length} warning lines; e.g. ${warnings[0].slice(0, 140)}`);
fs.writeFileSync(path.join(shots, 'log.txt'), out);
console.log(`> exit ${r.status} ${r.signal || ''}; log ${path.join(shots, 'log.txt')}`);
process.exit(errors.length ? 1 : (r.status ?? 1));
