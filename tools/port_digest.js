// port_digest.js -- the port to Anchor: the game's state at full precision (snakes, the lich, the
// director, the ending, the objects), as a JS expression for tools/shoot.mjs evals; its twin is
// tools/port_digest.lua (anchor drive eval: dofile). Compare with tools/port_digest_cmp.py.
(() => {
  const f = v => (Math.abs(v) < 1e-300 ? '0' : v.toPrecision(15));
  const out = [];
  out.push('t ' + G.tick);
  const L = G.mover.p; out.push('L ' + [L.x, L.y, L.z, G.mover.yaw].map(f).join(' '));
  for (const s of G.snakes.S) {
    const sp = s.spine;
    out.push('s ' + [s.x, s.z, s.dir, s.leak, s.delay, s.sink].map(f).join(' ') + ' ' + (s.fx ? 'fx' : '-') + (s.burn ? 'b' : '-') + (s.coil ? s.coil.phase : '-') + ' ' + [sp[0].x, sp[0].y, sp[0].z, sp[40].x, sp[40].y, sp[40].z, sp[71].x, sp[71].y, sp[71].z].map(f).join(' '));
  }
  const st = G.powers.state(); out.push('p ' + st.phase + ' ' + st.ab + ' ' + JSON.stringify(st.uses));
  const e = G.END; out.push('e ' + [e.w, e.level, e.grips].map(f).join(' '));
  const head = G.lich.nodes.head; head.updateWorldMatrix(true, false); const hp = head.getWorldPosition(new G.lich.root.position.constructor()); out.push('h ' + [hp.x, hp.y, hp.z].map(f).join(' '));
  out.push('i ' + JSON.stringify(GAME.items().map(w => w.balls ? [w.state].concat(...w.balls.map(b => b.slice(0,3))) : [w.state, w.x, w.y, w.z]))); return out.join('\n');
})()
