# store_gi.py -- bake the GI once in headless Chrome and store it in web/src/gi_data.js, so the
# page loads it instead of baking (~15 s). Run after any change to the cave's geometry or light.
#   python tools/store_gi.py
import json, os, subprocess, sys
root = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
os.chdir(root)
open('web/src/gi_data.js', 'w', encoding='utf-8').write('// gi_data.js -- the stored GI bake (tools/store_gi.py writes it; null = bake at load)\nexport const GI_DATA = null;\n')
os.makedirs('scratch/store_gi', exist_ok=True)
open('scratch/store_gi/s.json', 'w').write(json.dumps([{"eval": "JSON.stringify(G.cave.export_gi())"}, {"eval": "G.bake_ms"}]))
subprocess.run(['node', 'tools/shoot.mjs', 'web', 'scratch/store_gi/s.json', 'scratch/store_gi', '--size', '640x360'], check=True)
log = json.load(open('scratch/store_gi/log.json'))
if log['errors'] or log.get('fatal'): sys.exit('bake failed: %s %s' % (log['errors'][:2], log.get('fatal')))
data = log['evals'][0]['value']
open('web/src/gi_data.js', 'w', encoding='utf-8').write('// gi_data.js -- the stored GI bake, written by tools/store_gi.py (re-run it after any change\n// to the cave\'s geometry or light; a stale key makes the page bake at load instead)\nexport const GI_DATA = ' + data + ';\n')
print('stored GI: %d KB, bake took %s ms' % (len(data)//1024, log['evals'][1]['value']))
