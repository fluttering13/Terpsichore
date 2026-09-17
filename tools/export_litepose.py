"""Convert the attributed LitePose-S OpenVINO mirror to a mobile ONNX asset.

In an isolated Python environment install:
  torch onnx==1.22.0 onnxruntime==1.20.1 openvino==2025.0.0
  onnxifier==2.2.2 onnxscript==0.7.2
Run: python tools/export_litepose.py --work-dir <temporary-directory>
"""

import argparse
import hashlib
from pathlib import Path
import shutil
import subprocess
import urllib.request

import numpy as np
import onnx
import onnxruntime as ort
import openvino as ov
import torch
import torch.nn.functional as F

REVISION = '0de7ab36c9cf7d0843a1a19fd8c83db34a19d8a3'
BASE = f'https://huggingface.co/cansik/visiongraph/resolve/{REVISION}'
HASHES = {
    'xml': '040321c742d2f8d2910fdfcbf586a23203970d6fca55f3b4bb463ae07dff6d2c',
    'bin': '19c456294ab6ae6719175d7d8967d16577ebef3f6b431f9c0b0df08ce2c592c0',
}


class Candidates(torch.nn.Module):
    def forward(self, stage0, stage1):
        up = F.interpolate(stage0, size=(224, 224), mode='bilinear', align_corners=False)
        heat = (up[:, :17] + stage1) / 2
        tags = up[:, 17:]
        peaks = torch.where(heat == F.max_pool2d(heat, 5, 1, 2), heat, torch.zeros_like(heat))
        scores, indices = torch.topk(peaks.flatten(2), 5, dim=2)
        tag = torch.gather(tags.flatten(2), 2, indices)
        x = (indices % 224).float() / 224
        y = (indices // 224).float() / 224
        return torch.stack([x, y, scores, tag], dim=-1)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--work-dir', required=True, type=Path)
    args = parser.parse_args()
    work = args.work_dir.resolve()
    work.mkdir(parents=True, exist_ok=True)
    for ext, expected in HASHES.items():
        path = work / f'litepose.{ext}'
        if not path.exists():
            urllib.request.urlretrieve(f'{BASE}/litepose-auto-s-coco-fp32.{ext}', path)
        assert hashlib.sha256(path.read_bytes()).hexdigest() == expected, path

    converter = shutil.which('onnxify')
    if converter is None:
        raise RuntimeError('Activate the isolated environment containing onnxifier')
    raw = work / 'litepose.onnx'
    subprocess.run([converter, str(work / 'litepose.xml'), str(raw), '--opset-version', '17'], check=True)
    source = onnx.load(raw)
    session = ort.InferenceSession(str(raw), providers=['CPUExecutionProvider'])
    reference = ov.Core().compile_model(str(work / 'litepose.xml'), 'CPU', {'INFERENCE_PRECISION_HINT': 'f32'})
    # The IR includes mean subtraction, scale and channel reversal: input is
    # raw BGR (0..255), NCHW. Do not normalize it a second time in the app.
    data = np.random.default_rng(7).uniform(0, 255, (1, 3, 448, 448)).astype(np.float32)
    expected = list(reference([data]).values())
    actual = session.run(None, {session.get_inputs()[0].name: data})
    for lhs, rhs in zip(expected, actual):
        np.testing.assert_allclose(lhs, rhs, atol=0.002, rtol=0.002)
        print('OpenVINO/ORT max error:', float(np.max(np.abs(lhs - rhs))))

    head_path = work / 'head.onnx'
    head = Candidates().eval()
    torch.onnx.export(head, tuple(torch.from_numpy(x) for x in actual), str(head_path),
                      input_names=['stage0', 'stage1'], output_names=['candidates'], opset_version=17)
    tail = onnx.load(head_path)
    tail.ir_version = source.ir_version
    combined = onnx.compose.merge_models(source, tail, io_map=[
        (source.graph.output[0].name, 'stage0'), (source.graph.output[1].name, 'stage1'),
    ])
    onnx.checker.check_model(combined)
    destination = Path(__file__).resolve().parents[1] / 'asset/models/litepose_s_coco.onnx'
    destination.parent.mkdir(parents=True, exist_ok=True)
    onnx.save(combined, destination)
    mobile = ort.InferenceSession(str(destination), providers=['CPUExecutionProvider'])
    result = mobile.run(None, {mobile.get_inputs()[0].name: data})[0]
    target = head(*(torch.from_numpy(x) for x in actual)).detach().numpy()
    np.testing.assert_allclose(result, target, atol=0.002, rtol=0.002)
    print('Mobile output:', result.shape)
    print('SHA256:', hashlib.sha256(destination.read_bytes()).hexdigest())
    print('Saved:', destination)


if __name__ == '__main__':
    main()
