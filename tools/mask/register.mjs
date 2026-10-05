// node --import ./tools/mask/register.mjs tools/mask/build.mjs : 'three' and 'game/<file>.js' as the
// web build's import map gives them (three.js from the walk's node_modules, game/ = web/src/)
import { register } from 'node:module';
import { pathToFileURL } from 'node:url';
register(pathToFileURL(new URL('./hooks.mjs', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1')).href, import.meta.url);
