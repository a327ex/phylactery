import { pathToFileURL, fileURLToPath } from 'node:url';
import path from 'node:path';
const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..', '..');
const THREE = path.join(ROOT, 'archive', 'the-walk', 'tools', 'walk', 'node_modules', 'three', 'build', 'three.module.js');
export async function resolve(spec, ctx, next) {
  if (spec === 'three') return { url: pathToFileURL(THREE).href, shortCircuit: true };
  if (spec.startsWith('game/')) return { url: pathToFileURL(path.join(ROOT, 'web', 'src', spec.slice(5))).href, shortCircuit: true };
  return next(spec, ctx);
}
