"""Additional architectures from pinned Hugging Face revisions (weights only)."""
import hashlib
import json
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT=Path('build/pose-candidates')
SOURCES=[
 ('hrnet-w32','qualcomm/HRNetPose','416b07df7f0ba6961abe328a6687e48da2f3ed88','HRNetPose.onnx'),
 ('vitpose-small','onnx-community/vitpose-plus-small-ONNX','3fb96b7739ce774953b388d3339b4c39ed508d34','onnx/model.onnx'),
 ('movenet-lightning','Xenova/movenet-singlepose-lightning','ed0f314bb7356fd1dbf1e4f52c2d40791bf6534f','onnx/model.onnx'),
 ('movenet-thunder','Xenova/movenet-singlepose-thunder','38296077a99667cdad67af5096ce7eeb9b327453','onnx/model.onnx'),
 ('blazepose','opencv/pose_estimation_mediapipe','8cd55743af63a8578effaf144a68cb58f6450fe9','pose_estimation_mediapipe_2023mar.onnx'),
 ('blazepose-detector','opencv/person_detection_mediapipe','531b6da87204aa40aa5cc680b4d032dd09b5055e','person_detection_mediapipe_2023mar.onnx'),
]

def download(item):
    name,repo,revision,filename=item
    metadata=json.load(urllib.request.urlopen(f'https://huggingface.co/api/models/{repo}/revision/{revision}?blobs=true'))
    file=next(f for f in metadata['siblings'] if f['rfilename']==filename)
    sha=file['lfs']['sha256']; target=ROOT/(name+'.onnx')
    if not target.exists() or hashlib.sha256(target.read_bytes()).hexdigest()!=sha:
        print('Downloading',name,flush=True)
        temp=target.with_suffix('.partial')
        urllib.request.urlretrieve(f'https://huggingface.co/{repo}/resolve/{revision}/{filename}',temp)
        assert hashlib.sha256(temp.read_bytes()).hexdigest()==sha
        temp.replace(target)
    print('Verified',name,flush=True)
    return dict(name=name,repo=repo,revision=revision,file=filename,sha256=sha)

if __name__=='__main__':
    ROOT.mkdir(parents=True,exist_ok=True)
    with ThreadPoolExecutor(max_workers=3) as pool:manifest=list(pool.map(download,SOURCES))
    (ROOT/'diverse-sources.json').write_text(json.dumps(manifest,indent=2))
