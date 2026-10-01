"""Experimental symmetric per-output-channel INT8 weight storage for NLF.

Convolution/linear weights are stored as int8 and dequantized at use time.
Activations and compute retain their original floating dtype. This is NOT an
INT8-kernel mobile deployment. New scale attributes require load_quantized().
The original official checkpoint is never modified.
"""
import hashlib,json
import zipfile,re
import torch
import torchvision
from test_image_pose3d import OUT

TARGET=OUT/'models/nlf_l_multi_0.3.2.weight-int8.torchscript'

def load_quantized(device='cuda'):
    path=TARGET
    if device=='cpu':
        path=TARGET.with_name(TARGET.stem+'.cpu-fp32.torchscript')
        if not path.exists() or path.stat().st_mtime<TARGET.stat().st_mtime:
            with zipfile.ZipFile(TARGET) as src,zipfile.ZipFile(path,'w',compression=zipfile.ZIP_STORED) as dst:
                count=0
                for entry in src.infolist():
                    content=src.read(entry.filename)
                    if entry.filename.endswith('.py'):
                        content=re.sub(rb'torch.to\((im|images), 5\)',rb'torch.to(\1, 6)',content)
                        old=b'torch.grid_sampler(input, grid, mode_enum, padding_mode_enum, align_corners0)'
                        if old in content:
                            content=content.replace(old,b'torch.to(torch.grid_sampler(torch.to(input, 6), torch.to(grid, 6), mode_enum, padding_mode_enum, align_corners0), input)');count+=1
                    dst.writestr(entry,content)
                assert count==1,'Expected exactly one CPU grid-sampler compatibility patch'
    m=torch.jit.load(str(path),map_location='cpu').eval()
    if device=='cpu':m.float()
    m.to(device)
    for sub in m.modules():
        if device=='cpu' and hasattr(sub,'backbone_dtype'):sub.backbone_dtype=6
        if hasattr(sub,'_weight_scale'):
            sub._weight_scale=sub._weight_scale.to(device)
            if device=='cpu':sub._weight_scale=sub._weight_scale.float()
    return m

def rewrite(graph):
    if '_weight_scale' in str(graph):return
    def visit(block):
        for node in list(block.nodes()):
            for child in node.blocks():visit(child)
            if node.kind()!='prim::GetAttr' or node.s('name')!='weight':continue
            weight=node.output();users=list(weight.uses())
            scale=graph.create('prim::GetAttr',[node.inputsAt(0)]).s_('name','_weight_scale')
            scale.output().setType(torch._C.TensorType.get());scale.insertAfter(node)
            false=graph.create('prim::Constant').i_('value',0);false.output().setType(torch._C.BoolType.get());false.insertAfter(scale)
            none=graph.create('prim::Constant');none.output().setType(torch._C.NoneType.get());none.insertAfter(false)
            cast=graph.create('aten::to',[weight,scale.output(),false.output(),false.output(),none.output()])
            cast.output().setType(torch._C.TensorType.get());cast.insertAfter(none)
            mul=graph.create('aten::mul',[cast.output(),scale.output()]);mul.output().setType(torch._C.TensorType.get());mul.insertAfter(cast)
            for use in users:use.user.replaceInput(use.offset,mul.output())
    visit(graph);graph.lint()

def main():
    torch.set_num_threads(4)
    source=OUT/'models/nlf_l_multi_0.3.2.patch4.torchscript'
    m=torch.jit.load(str(source),map_location='cpu').eval()
    rows=[]
    for name,sub in m.named_modules():
        if getattr(sub,'original_name','') not in ['Conv2d','Linear']:continue
        w=sub.weight.detach();dims=tuple(range(1,w.ndim))
        scale=(w.float().abs().amax(dim=dims,keepdim=True)/127).clamp_min(1e-7).to(w.dtype)
        q=(w.float()/scale.float()).round().clamp(-127,127).to(torch.int8)
        error=(q.to(w.dtype)*scale-w).float().abs()
        rows.append({'name':name,'shape':list(w.shape),'source_dtype':str(w.dtype),'elements':w.numel(),'max_weight_error':float(error.max())})
        sub.weight=torch.nn.Parameter(q,requires_grad=False)
        sub._c._register_attribute('_weight_scale',torch._C.TensorType.get(),scale)
    for _,sub in m.named_modules():
        if not hasattr(sub,'_weight_scale'):continue
        for method in sub._c._method_names():rewrite(sub._c._get_method(method).graph)
    torch.jit.save(m,str(TARGET))
    # Verify storage dtype and graph survive serialization.
    reloaded=load_quantized('cpu')
    assert sum(p.numel() for p in reloaded.parameters() if p.dtype==torch.int8)==sum(r['elements'] for r in rows)
    report={'format':'Symmetric per-output-channel INT8 weights; floating activations/compute',
        'source_bytes':source.stat().st_size,'quantized_bytes':TARGET.stat().st_size,
        'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
        'quantized_sha256':hashlib.sha256(TARGET.read_bytes()).hexdigest(),
        'quantized_layers':len(rows),'layers':rows,'requires_loader':'tools/quantize_nlf.py:load_quantized',
        'limitations':['Not native INT8 convolution kernels','No mobile execution tested','No activation calibration needed for this weight-only method']}
    (OUT/'nlf-int8-conversion.json').write_text(json.dumps(report,indent=2),encoding='utf8')
    print({k:v for k,v in report.items() if k!='layers'},flush=True)

if __name__=='__main__':main()
