#!/bin/bash
# locate the best beam moment in each candidate (Gemini 3 Flash, YouTube low-res, 1 fps)
cd /c/Users/a327e/Desktop/a327ex/lich-survivors/reference/lasers
G=/c/Users/a327e/Desktop/tools/gemini
python -c "
import json
for c in json.load(open('candidates.json')): print(c['id'], c['url'], c['title'].replace(' ','_'))
" | while read id url title; do
  echo "$id $url $title"
done > locate/list.txt
run_one() {
  id=$1; url=$2; title=$3
  q=$(python -c "import sys; print(open('locate/q.txt').read() % sys.argv[1].replace('_',' '))" "$title")
  $G/venv/Scripts/python $G/gemini.py ask "$url" "$q" --fps 1 --res low --model gemini-3-flash-preview --slug "laser-$id" --out "locate/$id.txt" > "locate/$id.log" 2>&1
  echo "done $id"
}
export -f run_one; export G
cat locate/list.txt | xargs -P 4 -L 1 bash -c 'run_one "$0" "$1" "$2"'
