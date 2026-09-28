# Reference clips: download a short section of each video, make a small silent looping mp4 and a
# frame strip (for me to look at), all under reference/<topic>/.
#
#   python tools/refclips.py reference/lasers/clips.json
#
# clips.json: [{"id": "last-prism", "url": "...", "start": "1:02", "end": "1:08", ...}, ...]
# Writes reference/<topic>/clips/<id>.mp4 (<= 720p, no audio, ~8 s max) and <id>_strip.jpg.
# Skips clips already made. One download at a time (his machine is in use).
import json, os, subprocess, sys
from PIL import Image

FF = r'C:\Users\a327e\Desktop\tools\ffmpeg\bin'
FFMPEG = os.path.join(FF, 'ffmpeg.exe')

def secs(t):
    p = [float(x) for x in str(t).split(':')]
    return p[0]*60 + p[1] if len(p) == 2 else (p[0]*3600 + p[1]*60 + p[2] if len(p) == 3 else p[0])

def main(path):
    items = json.load(open(path, encoding='utf-8'))
    root = os.path.dirname(os.path.abspath(path))
    out = os.path.join(root, 'clips'); os.makedirs(out, exist_ok=True)
    raw = os.path.join(root, 'raw'); os.makedirs(raw, exist_ok=True)
    for it in items:
        cid = it['id']; mp4 = os.path.join(out, cid + '.mp4')
        if os.path.exists(mp4):
            continue
        a, b = secs(it['start']), secs(it['end'])
        b = min(b, a + 8.0)
        src = os.path.join(raw, cid + '.%(ext)s')
        r = subprocess.run(['yt-dlp', '--ffmpeg-location', FF, '-f', 'bv*[height<=720]+ba/b[height<=720]/bv*+ba/b',
                            '--download-sections', f'*{max(0, a - 0.5)}-{b + 0.5}', '--force-keyframes-at-cuts',
                            '-o', src, '--no-playlist', '--quiet', '--no-warnings', it['url']], capture_output=True, text=True)
        got = [f for f in os.listdir(raw) if f.startswith(cid + '.')]
        if r.returncode or not got:
            print('FAIL', cid, (r.stderr or '')[-300:]); continue
        f = os.path.join(raw, got[0])
        # a small silent loop: 720p at most, 30 fps
        subprocess.run([FFMPEG, '-y', '-loglevel', 'error', '-ss', '0.5', '-i', f, '-t', str(b - a), '-an', '-vf', 'scale=-2:min(720\\,ih),fps=30',
                        '-c:v', 'libx264', '-crf', '28', '-preset', 'slow', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', mp4], check=True)
        # a strip of 8 frames for looking at
        tmp = os.path.join(raw, cid + '_f%02d.jpg')
        n = 8
        subprocess.run([FFMPEG, '-y', '-loglevel', 'error', '-i', mp4, '-vf', f'fps={n/max(0.5, b - a)},scale=480:-2', '-frames:v', str(n), tmp], check=True)
        frames = [Image.open(tmp % (k + 1)) for k in range(n) if os.path.exists(tmp % (k + 1))]
        if frames:
            w, h = frames[0].size
            strip = Image.new('RGB', (w*4, h*((len(frames) + 3)//4)))
            for k, im in enumerate(frames): strip.paste(im, ((k % 4)*w, (k//4)*h))
            strip.save(os.path.join(out, cid + '_strip.jpg'), quality=85)
        print('ok', cid, os.path.getsize(mp4)//1024, 'KB')

if __name__ == '__main__':
    main(sys.argv[1])
