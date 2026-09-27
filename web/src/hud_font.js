// hud_font.js -- 5x7 pixel font for hud.js (uppercase, digits, common punctuation).
// Glyphs are proportional (trimmed to their used columns) except digits, which keep 5 columns
// so numbers do not jitter as they change.
const RAW = {
  A: ['.###.', '#...#', '#...#', '#####', '#...#', '#...#', '#...#'],
  B: ['####.', '#...#', '#...#', '####.', '#...#', '#...#', '####.'],
  C: ['.###.', '#...#', '#....', '#....', '#....', '#...#', '.###.'],
  D: ['####.', '#...#', '#...#', '#...#', '#...#', '#...#', '####.'],
  E: ['#####', '#....', '#....', '####.', '#....', '#....', '#####'],
  F: ['#####', '#....', '#....', '####.', '#....', '#....', '#....'],
  G: ['.###.', '#...#', '#....', '#.###', '#...#', '#...#', '.####'],
  H: ['#...#', '#...#', '#...#', '#####', '#...#', '#...#', '#...#'],
  I: ['###', '.#.', '.#.', '.#.', '.#.', '.#.', '###'],
  J: ['..###', '...#.', '...#.', '...#.', '...#.', '#..#.', '.##..'],
  K: ['#...#', '#..#.', '#.#..', '##...', '#.#..', '#..#.', '#...#'],
  L: ['#....', '#....', '#....', '#....', '#....', '#....', '#####'],
  M: ['#...#', '##.##', '#.#.#', '#.#.#', '#...#', '#...#', '#...#'],
  N: ['#...#', '#...#', '##..#', '#.#.#', '#..##', '#...#', '#...#'],
  O: ['.###.', '#...#', '#...#', '#...#', '#...#', '#...#', '.###.'],
  P: ['####.', '#...#', '#...#', '####.', '#....', '#....', '#....'],
  Q: ['.###.', '#...#', '#...#', '#...#', '#.#.#', '#..#.', '.##.#'],
  R: ['####.', '#...#', '#...#', '####.', '#.#..', '#..#.', '#...#'],
  S: ['.####', '#....', '#....', '.###.', '....#', '....#', '####.'],
  T: ['#####', '..#..', '..#..', '..#..', '..#..', '..#..', '..#..'],
  U: ['#...#', '#...#', '#...#', '#...#', '#...#', '#...#', '.###.'],
  V: ['#...#', '#...#', '#...#', '#...#', '#...#', '.#.#.', '..#..'],
  W: ['#...#', '#...#', '#...#', '#.#.#', '#.#.#', '#.#.#', '.#.#.'],
  X: ['#...#', '#...#', '.#.#.', '..#..', '.#.#.', '#...#', '#...#'],
  Y: ['#...#', '#...#', '.#.#.', '..#..', '..#..', '..#..', '..#..'],
  Z: ['#####', '....#', '...#.', '..#..', '.#...', '#....', '#####'],
  0: ['.###.', '#...#', '#...#', '#...#', '#...#', '#...#', '.###.'],   // open: a slashed zero read as S / 8 (a dotted one fills with ink under the outline)
  1: ['..#..', '.##..', '..#..', '..#..', '..#..', '..#..', '.###.'],
  2: ['.###.', '#...#', '....#', '...#.', '..#..', '.#...', '#####'],
  3: ['#####', '...#.', '..#..', '...#.', '....#', '#...#', '.###.'],
  4: ['...#.', '..##.', '.#.#.', '#..#.', '#####', '...#.', '...#.'],
  5: ['#####', '#....', '####.', '....#', '....#', '#...#', '.###.'],
  6: ['..##.', '.#...', '#....', '####.', '#...#', '#...#', '.###.'],
  7: ['#####', '....#', '...#.', '..#..', '.#...', '.#...', '.#...'],
  8: ['.###.', '#...#', '#...#', '.###.', '#...#', '#...#', '.###.'],
  9: ['.###.', '#...#', '#...#', '.####', '....#', '...#.', '.##..'],
  '.': ['.', '.', '.', '.', '.', '.', '#'],
  ',': ['..', '..', '..', '..', '..', '.#', '#.'],
  ':': ['.', '.', '#', '.', '.', '#', '.'],
  '!': ['#', '#', '#', '#', '#', '.', '#'],
  '?': ['.###.', '#...#', '....#', '...#.', '..#..', '.....', '..#..'],
  '-': ['....', '....', '....', '####', '....', '....', '....'],
  '+': ['.....', '..#..', '..#..', '#####', '..#..', '..#..', '.....'],
  '/': ['....#', '....#', '...#.', '..#..', '.#...', '#....', '#....'],
  '(': ['.#', '#.', '#.', '#.', '#.', '#.', '.#'],
  ')': ['#.', '.#', '.#', '.#', '.#', '.#', '#.'],
  "'": ['#', '#', '.', '.', '.', '.', '.'],
  '%': ['##..#', '##..#', '...#.', '..#..', '.#...', '#..##', '#..##'],
  '=': ['....', '....', '####', '....', '####', '....', '....'],
  '_': ['.....', '.....', '.....', '.....', '.....', '.....', '#####'],
  '|': ['#', '#', '#', '#', '#', '#', '#'],
  '<': ['...#', '..#.', '.#..', '#...', '.#..', '..#.', '...#'],
  '>': ['#...', '.#..', '..#.', '...#', '..#.', '.#..', '#...'],
  '[': ['##', '#.', '#.', '#.', '#.', '#.', '##'],
  ']': ['##', '.#', '.#', '.#', '.#', '.#', '##'],
};

export const GLYPH_H = 7;
export const FONT = {};
for (const ch in RAW) {
  const rows = RAW[ch];
  const w = rows[0].length;
  const px = [];
  for (let y = 0; y < GLYPH_H; y++) for (let x = 0; x < w; x++) if (rows[y][x] === '#') px.push(x, y);
  FONT[ch] = { w, px };
}
FONT[' '] = { w: 3, px: [] };

export function text_width(str, scale = 1) {
  let w = 0;
  for (const ch of String(str).toUpperCase()) w += ((FONT[ch] || FONT['?']).w + 1)*scale;
  return Math.max(0, w - scale);
}

// draw text at integer pixel coords; align 'left' | 'center' | 'right'
//   shadow   a colour: the whole text again, offset one font pixel down-right, under the fill
//   opts     optional: a colour string (= outline colour) or { outline: colour, shadow: colour }.
//            outline = a 1-px ink ring on all 8 neighbours of the lit pixels, painted before the fill,
//            each ring pixel exactly once (translucent ink never stacks into dark blobs), so the
//            text keeps its edges over busy textures. opts.shadow (with an outline) drops the ring
//            shape one pixel down as a soft second ink row.
const N8 = [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [-1, 1], [1, -1], [-1, -1]];
export function draw_text(g, str, x, y, color, scale = 1, align = 'left', shadow = null, opts = null) {
  str = String(str).toUpperCase();
  let cx = Math.round(align === 'center' ? x - text_width(str, scale)/2 : align === 'right' ? x - text_width(str, scale) : x);
  y = Math.round(y);
  const each = (fn) => {
    let px = cx;
    for (const ch of str) {
      const f = FONT[ch] || FONT['?'];
      for (let i = 0; i < f.px.length; i += 2) fn(px + f.px[i]*scale, y + f.px[i + 1]*scale);
      px += (f.w + 1)*scale;
    }
  };
  const pass = (ox, oy, c) => { g.fillStyle = c; each((px, py) => g.fillRect(px + ox, py + oy, scale, scale)); };
  const outline = typeof opts === 'string' ? opts : opts && opts.outline;
  if (shadow) pass(scale, scale, shadow);
  if (outline) {
    const K = (px, py) => (py + 2048)*8192 + px + 2048;
    const on = new Set(), ring = [], seen = new Set();
    each((px, py) => { for (let j = 0; j < scale; j++) for (let i = 0; i < scale; i++) on.add(K(px + i, py + j)); });
    each((px, py) => {
      for (let j = 0; j < scale; j++) for (let i = 0; i < scale; i++) for (const [dx, dy] of N8) {
        const qx = px + i + dx, qy = py + j + dy, k = K(qx, qy);
        if (on.has(k) || seen.has(k)) continue;
        seen.add(k); ring.push(qx, qy);
      }
    });
    const drop = typeof opts === 'object' && opts.shadow;
    if (drop) {
      g.fillStyle = drop;
      for (let i = 0; i < ring.length; i += 2) if (!seen.has(K(ring[i], ring[i + 1] + 1)) && !on.has(K(ring[i], ring[i + 1] + 1))) g.fillRect(ring[i], ring[i + 1] + 1, 1, 1);
    }
    g.fillStyle = outline;
    for (let i = 0; i < ring.length; i += 2) g.fillRect(ring[i], ring[i + 1], 1, 1);
  }
  pass(0, 0, color);
}
