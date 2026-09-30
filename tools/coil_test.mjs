// node tools/coil_test.mjs [mode] [seed] -- how many coiled snakes it takes to cover the egg
// (web/src/coil.js), settled bodies only, each along its band with the snake's radius profile.
import { create_coil } from '../web/src/coil.js';

const mode = +(process.argv[2] ?? 0), seed0 = +(process.argv[3] ?? 1);
const LEN = 4.4, R0 = 0.08, RINGS = 72;
const S_AT = i => LEN*Math.pow(i/(RINGS - 1), 1.6);
const lerp = (a, b, t) => a + (b - a)*t;
const smoothstep = (a, b, x) => { const t = Math.max(0, Math.min(1, (x - a)/(b - a))); return t*t*(3 - 2*t); };
function radius_at(s) {
  if (s < 0.012) return lerp(0.18, 0.45, s/0.012);
  if (s < 0.05) return lerp(0.45, 0.82, (s - 0.012)/0.038);
  if (s < 0.085) return lerp(0.82, 0.95, (s - 0.05)/0.035);
  if (s < 0.115) return lerp(0.95, 0.68, (s - 0.085)/0.03);
  if (s < 0.3) return lerp(0.68, 0.98, smoothstep(0.115, 0.3, s));
  const tail0 = LEN*0.62;
  if (s < tail0) return 1.0;
  return lerp(1.0, 0.07, Math.pow((s - tail0)/(LEN - tail0), 0.85));
}
const make_rng = (s) => { let x = s >>> 0 || 1; return { next() { x ^= x << 13; x >>>= 0; x ^= x >> 17; x ^= x << 5; x >>>= 0; return x/4294967296; } }; };

for (let seed = seed0; seed < seed0 + 5; seed++) {
  const rng = make_rng(seed*7919);
  const coil = create_coil({ centre: [0, 0.37, 0], ground_y: () => 0, rng, len: LEN });
  const bodies = [], planned = [];
  let mask = new Uint8Array(coil.samples.length);
  const out = [];
  for (let n = 1; n <= 14; n++) {
    const th = rng.next()*Math.PI*2;
    const d_b = coil.base_dir(Math.cos(th)*1.1, Math.sin(th)*1.1, 0.067);
    const p = coil.plan(mode, d_b, [-Math.cos(th), -Math.sin(th)], planned, mask);
    planned.push(p.band);
    const B = p.band, A = B.arc, total = A[A.length - 1];
    const foot = [], rad = [], on = [];
    const q = [0, 0, 0], nn = [0, 0, 0];
    for (let i = 0; i < RINGS; i++) {
      const a = total - S_AT(i);               // head at the band's end
      let j = A.findIndex(x => x >= a); if (j <= 0) j = 1;
      const f = (a - A[j - 1])/((A[j] - A[j - 1]) || 1);
      const d0 = B.dirs[j - 1], d1 = B.dirs[j];
      const d = [d0[0] + (d1[0] - d0[0])*f, d0[1] + (d1[1] - d0[1])*f, d0[2] + (d1[2] - d0[2])*f];
      const l = Math.hypot(...d); d[0] /= l; d[1] /= l; d[2] /= l;
      coil.surface(d, q, nn);
      foot.push(q.slice()); rad.push(R0*radius_at(S_AT(i))); on.push(true);
    }
    bodies.push({ foot, rad, on });
    const c = coil.coverage(bodies, mask);
    out.push(`${n}:${(c*100).toFixed(0)}%${B.stacked !== undefined ? 's' : ''}${B.turns ? '(' + B.turns.toFixed(1) + 't)' : ''}`);
    if (c > 0.985) break;
  }
  console.log(`seed ${seed}: ${out.join(' ')}`);
}
