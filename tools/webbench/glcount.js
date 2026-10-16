// webbench/glcount.js -- evaluated in the bench page by run.mjs (WEBBENCH_GLCOUNT=1) during the fight (2026-10-16,
// Phylactery 19): every WebGL call the page makes, counted by name, with the time spent inside each (performance.now
// around the call, so the wrapper's own cost is in it too) over 600 animation frames; window.__GLC.report() after.
(function () {
  var gl = (typeof GLctx !== 'undefined' && GLctx) || (window.Module && Module.ctx);
  if (!gl) return 'no GL context';
  var C = window.__GLC = { n: {}, t: {}, frames: 0, on: true, t0: performance.now(), t1: 0 };
  var proto = Object.getPrototypeOf(gl);
  Object.getOwnPropertyNames(proto).forEach(function (k) {
    var d = Object.getOwnPropertyDescriptor(proto, k);
    if (!d || typeof d.value !== 'function' || k === 'constructor') return;
    var f = d.value;
    gl[k] = function () {
      if (!C.on) return f.apply(gl, arguments);
      var t = performance.now();
      var r = f.apply(gl, arguments);
      C.t[k] = (C.t[k] || 0) + performance.now() - t;
      C.n[k] = (C.n[k] || 0) + 1;
      return r;
    };
  });
  var raf = window.requestAnimationFrame;
  var tick = function () { if (C.on) { C.frames++; if (C.frames >= 600) { C.on = false; C.t1 = performance.now(); } raf(tick); } };
  raf(tick);
  C.report = function () {
    var ks = Object.keys(C.n).sort(function (a, b) { return C.n[b] - C.n[a]; });
    var tot = 0, tt = 0;
    var lines = ks.map(function (k) { tot += C.n[k]; tt += C.t[k]; return k + ' ' + (C.n[k]/C.frames).toFixed(1) + ' a frame, ' + (C.t[k]/C.frames).toFixed(3) + ' ms'; });
    return 'GL calls over ' + C.frames + ' animation frames: ' + (tot/C.frames).toFixed(0) + ' a frame, ' + (tt/C.frames).toFixed(2) + ' ms inside them\n' + lines.slice(0, 40).join('\n');
  };
  return 'counting';
})()
