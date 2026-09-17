"""Download pinned experimental models into ignored build/, never app assets."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import urllib.request
import hashlib
import onnxruntime as ort

MODELS = [
 ('yolo11s-pose','AXERA-TECH/YOLO11-Pose','156938308275ed3dbe3772898d8766a399aeb173','yolo11s-pose.onnx'),
 ('rtmpose-s','bukuroo/RTMPose-ONNX','a6e9fb8a9190efd0383b059033f45645180cc7df','rtmpose-s.onnx'),
 ('rtmpose-m-wholebody','bukuroo/RTMPose-ONNX','a6e9fb8a9190efd0383b059033f45645180cc7df','rtmpose-m-wholebody.onnx'),
]
HASHES = {
 'yolo11s-pose': 'c53f26bdad7b89da6e673dc3b59fa2062c21b78ceff65c14d55639d691578208',
 'rtmpose-s': '8069eb32a037dd57abc1cfc078521dde49797c955232d40dae54b677182c2f7f',
 'rtmpose-m-wholebody': '465259a2e6c0f434ec5a5097640d6a439106c423e942ddbab7c6eaa02cc00c8a',
}
def download(model):
    name,repo,rev,file = model
    target = Path('build/pose-candidates') / file
    target.parent.mkdir(exist_ok=True)
    if not target.exists():
        urllib.request.urlretrieve(f'https://huggingface.co/{repo}/resolve/{rev}/{file}',target)
    digest = hashlib.sha256(target.read_bytes()).hexdigest()
    if digest != HASHES[name]:
        raise RuntimeError(f'Model hash mismatch: {target}')
    options=ort.SessionOptions(); options.intra_op_num_threads=2
    options.log_severity_level=3
    session=ort.InferenceSession(str(target),options,providers=['CPUExecutionProvider'])
    print(name,target.stat().st_size,digest,[(x.name,x.shape) for x in session.get_inputs()],[(x.name,x.shape) for x in session.get_outputs()],flush=True)
with ThreadPoolExecutor(max_workers=3) as pool:
    list(pool.map(download,MODELS))
