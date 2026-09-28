# Builds the laser reference board: one self-contained page (videos and stills embedded).
#   python board.py ../../rounds/12-laser-references/index.html
import base64, html, sys

def b64(path, mime):
    return f'data:{mime};base64,' + base64.b64encode(open(path, 'rb').read()).decode()

# (id, source title, url with time, beam: A prismatic / B lens, what it offers)
A = [
    ('last-prism', 'Terraria: Last Prism', 'https://www.youtube.com/watch?v=ovWxzlEKMjw&t=298',
     'Six coloured beams swing in and converge into one thick white beam in a rainbow sheath. It pulses and sheds prismatic sparks. The idea to take: light gathering into one beam.'),
    ('disintegrate', 'Diablo 3: Disintegrate', 'https://www.youtube.com/watch?v=f_JUxbp0Fhs',
     'Seen from above like our room camera. A beam from the hand with a hot flare at both ends; it sweeps smoothly from one target to the next.'),
    ('ray-of-frost', 'Diablo 3: Ray of Frost', 'https://www.youtube.com/watch?v=klT9wjKKSDM',
     'Thin, pale and precise, a white-hot point at the hand and at the hit. It still reads at a small size from high above.'),
    ('prism-real', 'Real: white light through a prism', 'https://www.youtube.com/watch?v=9eEyTw4wylk&t=38',
     'What dispersion really looks like: one white ray leaves the glass as an ordered band, red on one edge to violet on the other, soft-edged.'),
    ('divinity', 'Destiny 2: Divinity', 'https://www.youtube.com/watch?v=L3c9rXdUN-Y&t=69',
     'Secondary. A white-blue core with violet crackle along it, ending in a cage of light on the target.'),
]
B = [
    ('vfx-vertical', 'Tutorial preview: a vertical beam (Unreal Niagara)', 'https://www.youtube.com/watch?v=NbbFytz-JDk',
     'A beam coming down from above: strands scrolling down inside a hot core, a ring of light and a burst of sparks where it lands. The closest to a lens beam from the shaft.'),
    ('stone-titan', 'Risk of Rain 2: Stone Titan', 'https://www.youtube.com/watch?v=d5oPQamOt6g&t=32',
     'A red glow charges at the eye first, then a thick beam tracks across the ground, the hit point bursting.'),
    ('returnal-phrike', 'Returnal: Phrike', 'https://www.youtube.com/watch?v=RmRxaIjsSjk&t=204',
     'Orange beams with white cores, flickering along their length, shedding sparks as they sweep across the floor.'),
    ('scorching-ray', 'Path of Exile: Scorching Ray', 'https://www.youtube.com/watch?v=au45-m4fzxg&t=10',
     'A golden beam with rings travelling along it, a burning ball where it hits, heat shimmer around it.'),
    ('magnified-fire', 'Real: sunlight through a lens', 'https://www.youtube.com/watch?v=Ko_2BFGuudk&t=44',
     'A real lens: the focus is a tiny blinding spot, the material smokes at once and a black scorch spreads.'),
    ('incinerate', 'Diablo 4: Incinerate', 'https://www.youtube.com/watch?v=r9Vp1hSSjSQ',
     'Secondary. A channelled fire beam wrapped in flames and swirls, a spinning ring of fire at the impact.'),
]
BOTH = [
    ('vfx-stylized', 'Tutorial preview: a stylized beam (Unity VFX Graph)', 'https://www.youtube.com/watch?v=_SaBXY-Ejqo',
     'A glowing ball at the origin, electric strands flowing along the beam, sparks spraying off the end.'),
    ('laser-fog', 'Real: lasers in haze', 'https://www.youtube.com/watch?v=nxc_ZuiaMSU&t=537',
     'Real beams are thin, hard lines that only show where the air holds something (smoke, dust), brighter where it is thick.'),
]
QUALITIES = [
    ('Layers', 'a white-hot core inside a coloured glow, not one flat line'),
    ('Energy running along it', 'streaks, strands or rings travelling the length of the beam'),
    ('A flicker', 'its width and brightness trembling all the time'),
    ('Onset', 'a charge or gathering at the source first, then the beam shoots out to the target'),
    ('Offset', 'it thins out and fades rather than vanishing'),
    ('Source flare', 'a hot point at the fingertip (or the lens) while it fires'),
    ('Impact', 'a splash where it hits: a flare, sparks, a ring on the floor'),
    ('Light and shake', 'it lights the room around it; the screen shakes when it hits'),
    ('Spectral order', 'for the prismatic beam: fringes in order, red on one side to violet on the other'),
    ('Haze', 'the beam catching dust in the air, like the shaft of light already does'),
    ('Scorch', 'for the lens: a burnt line left on the floor where the spot passed'),
]

def card(c, tag):
    cid, title, url, note = c
    return f'''<figure class="card"><video src="{b64(f'web/{cid}.mp4', 'video/mp4')}" autoplay muted loop playsinline></video>
<figcaption><span class="tag {tag.lower()}">{tag}</span><b>{html.escape(title)}</b><p>{html.escape(note)}</p><a href="{url}" target="_blank" rel="noopener">source</a></figcaption></figure>'''

def section(title, sub, items, tag):
    return f'<section><h2>{title}</h2><p class="sub">{sub}</p><div class="grid">' + ''.join(card(c, tag) for c in items) + '</div></section>'

page = f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Laser References</title>
<style>
:root {{ --bg:#0f0c09; --panel:#1a1511; --ink:#efe2c8; --dim:#a8987c; --line:#2e261e; --a:#c9b8ff; --b:#ffb36b; --both:#9fd8c8; }}
* {{ box-sizing:border-box; }}
body {{ margin:0; background:var(--bg); color:var(--ink); font:15px/1.5 system-ui, -apple-system, Segoe UI, sans-serif; }}
main {{ max-width:1240px; margin:0 auto; padding:28px 16px 60px; }}
h1 {{ font-size:22px; margin:0 0 6px; letter-spacing:.02em; }}
h2 {{ font-size:17px; margin:34px 0 2px; }}
.sub, .lead {{ color:var(--dim); margin:0 0 14px; max-width:820px; }}
.grid {{ display:grid; grid-template-columns:repeat(auto-fill, minmax(340px, 1fr)); gap:14px; }}
.card {{ margin:0; background:var(--panel); border:1px solid var(--line); border-radius:8px; overflow:hidden; }}
.card video, .card img {{ width:100%; display:block; aspect-ratio:16/9; object-fit:cover; background:#000; }}
figcaption {{ padding:10px 12px 12px; }}
figcaption b {{ display:block; margin:4px 0 2px; }}
figcaption p {{ margin:0 0 6px; color:#d8cab0; font-size:14px; }}
figcaption a {{ color:var(--dim); font-size:13px; }}
.tag {{ display:inline-block; font-size:11px; font-weight:700; letter-spacing:.06em; padding:1px 7px; border-radius:3px; color:#120e0a; }}
.tag.a {{ background:var(--a); }} .tag.b {{ background:var(--b); }} .tag.both {{ background:var(--both); }}
.ours {{ display:grid; grid-template-columns:repeat(auto-fill, minmax(340px, 1fr)); gap:14px; }}
ol {{ padding-left:22px; max-width:900px; }} ol li {{ margin:4px 0; }} ol b {{ color:var(--ink); }} ol span {{ color:var(--dim); }}
</style></head><body><main>
<h1>Laser references</h1>
<p class="lead">For the two beams: <b style="color:var(--a)">A</b>, the prismatic beam from his finger, and <b style="color:var(--b)">B</b>, the lens's burning beam from the shaft of light. Pick the clips (or the qualities below) each beam should follow. Clips loop; "source" opens the original at the moment.</p>
<section><h2>Ours now</h2><p class="sub">Round 11: a static line each, no movement along it, no onset, almost no impact.</p><div class="ours">
<figure class="card"><img src="{b64('web/ours-beam.jpg', 'image/jpeg')}"><figcaption><span class="tag a">A</span><b>The prismatic beam</b><p>A white line with faint red and blue fringes, there for a quarter of a second.</p></figcaption></figure>
<figure class="card"><img src="{b64('web/ours-lens.jpg', 'image/jpeg')}"><figcaption><span class="tag b">B</span><b>The lens beams (four, the lens alone)</b><p>Orange lines from above to a small hot spot with sparks.</p></figcaption></figure>
</div></section>
{section('A: the prismatic beam', 'From his fingertip, piercing a snake and chaining to the next.', A, 'A')}
{section('B: the lens beam', 'Sunlight gathered by a lens in the shaft, one hot beam down to the floor, sweeping and cutting.', B, 'B')}
{section('Both', 'How beams are built, and how real ones look in the air.', BOTH, 'BOTH')}
<section><h2>Qualities to pick from</h2><p class="sub">What these references do that ours doesn't; name any for either beam.</p><ol>
{''.join(f'<li><b>{html.escape(a)}</b>: <span>{html.escape(b)}</span></li>' for a, b in QUALITIES)}
</ol></section>
</main></body></html>'''
open(sys.argv[1], 'w', encoding='utf-8').write(page)
print(sys.argv[1], len(page)//1024, 'KB')
