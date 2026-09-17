"""Download pinned Hugging Face ONNX weights; never execute remote code."""
import hashlib
import json
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path('build/pose-candidates')
SOURCES = [
    ('bukuroo/RTMPose-ONNX', 'a6e9fb8a9190efd0383b059033f45645180cc7df',
     ['rtmpose-m', 'rtmpose-l', 'rtmpose-x']),
    ('Xenova/yolov8-pose-onnx', '393fd4608bd8da7b1f636a7d9cb098321ccba4bf',
     ['yolov8n-pose', 'yolov8s-pose', 'yolov8m-pose']),
]

def download(item):
    repo, revision, file = item
    target = ROOT / file['rfilename']
    sha = file['lfs']['sha256']
    if not target.exists() or hashlib.sha256(target.read_bytes()).hexdigest() != sha:
        print('Downloading', target.name, flush=True)
        temp = target.with_suffix('.partial')
        urllib.request.urlretrieve(f'https://huggingface.co/{repo}/resolve/{revision}/{target.name}', temp)
        assert hashlib.sha256(temp.read_bytes()).hexdigest() == sha
        temp.replace(target)
    print('Verified', target.name, flush=True)
    return dict(repo=repo, revision=revision, file=target.name, sha256=sha)

if __name__ == '__main__':
    ROOT.mkdir(parents=True, exist_ok=True)
    jobs = []
    for repo, revision, names in SOURCES:
        metadata = json.load(urllib.request.urlopen(f'https://huggingface.co/api/models/{repo}/revision/{revision}?blobs=true'))
        jobs += [(repo, revision, f) for f in metadata['siblings'] if f['rfilename'] in [n+'.onnx' for n in names]]
    assert len(jobs) == 6
    with ThreadPoolExecutor(max_workers=3) as pool:
        manifest = list(pool.map(download, jobs))
    (ROOT / 'expanded-sources.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
