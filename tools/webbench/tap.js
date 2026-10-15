// webbench/tap.js -- evaluated in the bench page by run.mjs (WEBBENCH_TAP=1) once the engine's audio output exists
// (2026-10-15, Phylactery 19: "it stutters and repeats portions of the sound" was still there after the 4096 blocks).
// Two streams, so nothing has to be inferred from callback timings:
//   eng -- everything the engine mixed, in order: the engine's own web output (Anchor 2026-10-15: Module.__aud, the
//          chunks web_audio_pump posts), or on an older engine miniaudio's ScriptProcessorNode blocks (onaudioprocess
//          wrapped, its output buffer copied after it ran)
//   out -- what the browser really plays: an AudioWorklet fed by that output node, every 128-frame quantum copied on
//          the audio thread (so its record is exact even when the main thread is late)
// tools/webbench/tap_check.py follows one through the other: sound played twice, skipped, or a gap shows.
(async function () {
  var A = window.Module && Module.__aud;
  var m = window.miniaudio, d = m && m.devices && m.devices[0];
  var ctx, src, path;
  if (A && A.node) { ctx = A.ctx; src = A.node; path = A.mode; }
  else if (d && d.scriptNode && d.webaudio) { ctx = d.webaudio; src = d.scriptNode; path = 'device'; }
  else return 'no device';
  var T = window.__TAP = { eng: [], out: [], stop: false };
  if (path === 'device') {
    var orig = d.scriptNode.onaudioprocess;
    d.scriptNode.onaudioprocess = function (e) {
      var t = performance.now();
      orig(e);
      if (T.stop) return;
      var ob = e.outputBuffer, L = ob.getChannelData(0), R = ob.getChannelData(ob.numberOfChannels > 1 ? 1 : 0);
      var c = new Float32Array(L.length * 2);
      for (var i = 0; i < L.length; i++) { c[2*i] = L[i]; c[2*i + 1] = R[i]; }
      T.eng.push([t, c]);
    };
  } else if (path === 'worklet') {
    var port = A.node.port, post = port.postMessage.bind(port);
    port.postMessage = function (c, tr) { if (!T.stop && c && c.length) T.eng.push([performance.now(), c.slice()]); return post(c, tr); };
  } else {
    A.q.push = function (c) { if (!T.stop) T.eng.push([performance.now(), c.slice()]); return Array.prototype.push.call(this, c); };
  }
  var rec = 'class TapRec extends AudioWorkletProcessor {\n' +
    '  process(inputs, outputs) {\n' +
    '    var i = inputs[0];\n' +
    '    if (i && i.length) this.port.postMessage([currentFrame, i[0].slice(0), (i[1] || i[0]).slice(0)]);\n' +
    '    else this.port.postMessage([currentFrame, null, null]);\n' +
    '    return true;\n' +
    '  }\n' +
    '}\n' +
    'registerProcessor("taprec", TapRec);\n';
  // a data: URL: from file:// the page's origin is null, and a blob: module then counts as cross-origin
  await ctx.audioWorklet.addModule('data:application/javascript;base64,' + btoa(rec));
  var node = new AudioWorkletNode(ctx, 'taprec', { numberOfInputs: 1, numberOfOutputs: 1, outputChannelCount: [2],
    channelCount: 2, channelCountMode: 'explicit', channelInterpretation: 'discrete' });
  node.port.onmessage = function (ev) { if (!T.stop) T.out.push(ev.data); };
  src.connect(node);
  node.connect(ctx.destination);           // pulled by the graph; it outputs silence, so the mix is unchanged
  T.pack = function () {
    T.stop = true;
    var en = 0, on = 0;
    T.eng.forEach(function (b) { en += b[1].length; });
    T.out.forEach(function (q) { on += 2 * (q[1] ? q[1].length : 128); });
    var eb = new Float32Array(en), ob = new Float32Array(on), p = 0;
    var emeta = T.eng.map(function (b) { eb.set(b[1], p); p += b[1].length; return [b[0], b[1].length >> 1]; });
    p = 0;
    var ometa = T.out.map(function (q) {
      var n = q[1] ? q[1].length : 128;
      if (q[1]) for (var i = 0; i < n; i++) { ob[p + 2*i] = q[1][i]; ob[p + 2*i + 1] = q[2][i]; }
      p += 2 * n;
      return [q[0], n, q[1] ? 1 : 0];
    });
    T.bytes = { eng: new Uint8Array(eb.buffer), out: new Uint8Array(ob.buffer) };
    var st = {};
    if (A) { st = { heardRuns: A.heardRuns, heardMs: A.heardFrames * 1000 / A.rate, runsSeen: A.runsSeen, leadMs: A.lead * 1000 / A.rate }; }
    return { path: path, rate: ctx.sampleRate, eng_chunks: emeta.length, out_quanta: ometa.length,
      eng_bytes: T.bytes.eng.length, out_bytes: T.bytes.out.length, eng_meta: emeta, out_meta: ometa, out_stats: st,
      bench: (window.BENCH && window.BENCH.lines) || [] };
  };
  T.slice = function (name, off, len) {
    var u = T.bytes[name].subarray(off, off + len), s = '';
    for (var i = 0; i < u.length; i += 0x8000) s += String.fromCharCode.apply(null, u.subarray(i, i + 0x8000));
    return btoa(s);
  };
  return 'on: ' + path + ' at ' + ctx.sampleRate + ' Hz, context ' + ctx.state;
})()
