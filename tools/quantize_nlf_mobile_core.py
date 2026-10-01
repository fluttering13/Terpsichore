"""Calibrate on A only and validate all formats on held-out B crop samples."""
import json,time
import numpy as np
import onnx,onnxruntime as ort
import torch,torchvision
from onnxruntime.quantization import quantize_static,CalibrationDataReader,QuantType,QuantFormat
from onnxruntime.transformers.float16 import convert_float_to_float16
from export_nlf_mobile_core import MOBILE
from quantize_nlf import load_quantized

class Reader(CalibrationDataReader):
    def __init__(self,samples):self.items=iter([s for s in samples if s['calibration']])
    def get_next(self):
        s=next(self.items,None)
        return None if s is None else {'image':np.load(MOBILE/(s['tag']+'.npy'))}

def main():
    samples=json.loads((MOBILE/'samples.json').read_text())
    fp=MOBILE/'nlf-l-core-fp32.onnx';half=MOBILE/'nlf-l-core-fp16.onnx';q=MOBILE/'nlf-l-core-qdq-int8.onnx'
    print('float16 conversion',flush=True)
    if not half.exists():onnx.save(convert_float_to_float16(onnx.load(fp),keep_io_types=True),half)
    print('INT8 calibration: A only',flush=True)
    if not q.exists():quantize_static(str(fp),str(q),Reader(samples),quant_format=QuantFormat.QDQ,
        activation_type=QuantType.QUInt8,weight_type=QuantType.QInt8,per_channel=True,op_types_to_quantize=['Conv','MatMul','Gemm'])
    torch.set_num_threads(4);model=load_quantized('cpu');report={'calibration':'A eight sampled frames only; B held out','formats':{}}
    for name,path in [('fp32',fp),('fp16',half),('qdq-int8',q)]:
        options=ort.SessionOptions();options.intra_op_num_threads=8;options.inter_op_num_threads=1
        start=time.perf_counter();session=ort.InferenceSession(str(path),options,providers=['CPUExecutionProvider'])
        row={'bytes':path.stat().st_size,'load_seconds':time.perf_counter()-start,'samples':[]}
        for sample in samples:
            tag=sample['tag'];ref=np.load(MOBILE/f'{tag}-reference.npz')
            start=time.perf_counter();outputs=session.run(None,{'image':np.load(MOBILE/f'{tag}.npy')});elapsed=time.perf_counter()-start
            with torch.inference_mode():
                pose,_=model.crop_model.heatmap_head.reconstruct_absolute(*[torch.from_numpy(v) for v in outputs],torch.from_numpy(ref['K']))
                raw=(pose@torch.from_numpy(ref['R']))[0].numpy()/1000
            diff=np.linalg.norm((raw-raw[:1])-(ref['raw']-ref['raw'][:1]),axis=-1)*1000
            row['samples'].append({'tag':tag,'seconds':elapsed,'mean_root_relative_difference_mm':float(diff.mean()),'max_root_relative_difference_mm':float(diff.max())})
            np.savez(MOBILE/f'{tag}-{name}-outputs.npz',coords2d=outputs[0],coords3d=outputs[1],uncertainty=outputs[2],raw=raw)
        report['formats'][name]=row
        (MOBILE/'conversion-validation.json').write_text(json.dumps(report,indent=2))
        print(name,'bytes',row['bytes'],'B mean mm',np.mean([r['mean_root_relative_difference_mm'] for r in row['samples'] if r['tag'].startswith('B')]),flush=True)
        del session
if __name__=='__main__':main()
