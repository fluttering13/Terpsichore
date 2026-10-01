"""Package the calibrated NLF core with its mirrored canonical query head.

Run in build/pose3d-image-env. Backbone stays QDQ INT8; mirrored head is FP32.
Normal outputs must remain bit-identical to the calibrated model.
"""
import copy
import hashlib
import json
from pathlib import Path
import numpy as np
import onnx
from onnx import numpy_helper
import onnxruntime as ort
import torch

ROOT = Path(__file__).resolve().parents[1]
MODELS = ROOT / 'build/pose3d-poc/models'
MOBILE = MODELS / 'nlf-mobile'
DEST = ROOT / 'android/app/src/main/assets/pose3d'


def main():
    DEST.mkdir(parents=True, exist_ok=True)
    src = onnx.load(MOBILE / 'nlf-l-core-fp32.onnx')
    dst = onnx.load(MOBILE / 'nlf-l-core-qdq-int8.onnx')
    head = next(n for n in src.graph.node if n.name == '/Conv')
    qhead = next(n for n in dst.graph.node if n.name == '/Conv')
    producers = {o: n for n in src.graph.node for o in n.output}
    needed = set()
    def visit(name):
        if name == head.input[0] or name not in producers:
            return
        node = producers[name]
        if node.name in needed:
            return
        needed.add(node.name)
        for i in node.input:
            visit(i)
    for out in src.graph.output:
        visit(out.name)
    chosen = [n for n in src.graph.node if n.name in needed]
    rename = {o: o + '_flipped' for n in chosen for o in n.output}
    rename[head.input[0]] = qhead.input[0]
    weights = torch.load(MODELS / 'nlf-l-h36m17-query-weights.pt', weights_only=True)
    initializers = {i.name: i for i in src.graph.initializer}
    used = {i for n in chosen for i in n.input if i in initializers}
    for name in used:
        arr = numpy_helper.to_array(initializers[name])
        if name == head.input[1]:
            arr = weights['w_tensor_flipped'].numpy().reshape(arr.shape).astype(np.float32)
        elif name == head.input[2]:
            arr = weights['b_tensor_flipped'].numpy().reshape(arr.shape).astype(np.float32)
        rename[name] = name + '_flipped'
        dst.graph.initializer.append(numpy_helper.from_array(arr.copy(), rename[name]))
    for node in chosen:
        n = copy.deepcopy(node)
        n.name += '_flipped'
        for i, name in enumerate(n.input):
            n.input[i] = rename.get(name, name)
        for i, name in enumerate(n.output):
            n.output[i] = rename[name]
        dst.graph.node.append(n)
    for output in src.graph.output:
        out = copy.deepcopy(output)
        out.name = rename[out.name]
        dst.graph.output.append(out)
    onnx.checker.check_model(dst)
    target = DEST / 'nlf-l-int8.onnx'
    onnx.save(dst, target)
    opts = ort.SessionOptions()
    opts.intra_op_num_threads = 4
    before = ort.InferenceSession(str(MOBILE / 'nlf-l-core-qdq-int8.onnx'), opts)
    after = ort.InferenceSession(str(target), opts)
    for tag in ['A-000', 'B-030']:
        x = np.load(MOBILE / (tag + '.npy'))
        a, b = before.run(None, {'image': x}), after.run(None, {'image': x})
        for u, v in zip(a, b[:3]):
            np.testing.assert_array_equal(u, v)
        assert all(np.isfinite(v).all() for v in b)
    # Check the new mirrored query head against the original TorchScript decoder,
    # using the exact same quantized-backbone feature tensor.
    import torchvision  # registers the original model's scripted NMS operator
    from quantize_nlf import load_quantized
    dst.graph.output.append(onnx.helper.make_tensor_value_info(qhead.input[0], onnx.TensorProto.FLOAT, None))
    probe_path = MOBILE / 'nlf-head-validation.onnx'
    onnx.save(dst, probe_path)
    try:
        probe = ort.InferenceSession(str(probe_path), opts)
        outputs = probe.run(None, {'image': np.load(MOBILE / 'B-030.npy')})
        original = load_quantized('cpu')
        with torch.inference_mode():
            ref = original.crop_model.heatmap_head.decode_features_multi_same_weights(
                torch.from_numpy(outputs[-1]), weights, torch.tensor([True]))
        errors = [float(np.abs(a-b.numpy()).max()) for a,b in zip(outputs[3:6],ref)]
        assert max(errors) < .002, errors
        print('Mirrored-head max errors:', errors)
        del probe, original
    finally:
        probe_path.unlink(missing_ok=True)
    manifest = {p.name: {'bytes': p.stat().st_size, 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()}
                for p in DEST.iterdir() if p.suffix == '.onnx'}
    (DEST / 'manifest.json').write_text(json.dumps(manifest, indent=2))
    print(json.dumps(manifest, indent=2))


if __name__ == '__main__':
    main()
