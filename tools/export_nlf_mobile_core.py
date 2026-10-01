"""Static 17-joint NLF core for ONNX/Android, plus real-image calibration inputs.

Core returns crop 2D, relative 3D and uncertainty. Perspective reconstruction,
full-frame warping and augmentation fusion remain outside this ONNX artifact.
"""
import json,sys,time
import numpy as np
import torch,torchvision
from test_image_pose3d import OUT,input_frames
from quantize_nlf import load_quantized

MOBILE=OUT/'models/nlf-mobile'
class Core(torch.nn.Module):
    def __init__(self,crop,weights):
        super().__init__();self.crop=crop
        self.register_buffer('w',weights['w_tensor']);self.register_buffer('b',weights['b_tensor'])
        self.side=crop.heatmap_head.proc_side;self.stride=crop.heatmap_head.stride_test
        self.centered=crop.heatmap_head.centered_stride;self.box=crop.heatmap_head.box_size_m
        with torch.inference_mode(): self.feature_shape=tuple(crop.get_features(torch.zeros(1,3,384,384)).shape)
        self.depth=crop.heatmap_head.depth
        self.ub=crop.heatmap_head.uncert_bias;self.ub2=crop.heatmap_head.uncert_bias2
    def forward(self,x):
        f=self.crop.get_features(x).reshape(self.feature_shape)
        _,channels,h,w=self.feature_shape;d=self.depth
        logits=torch.nn.functional.conv2d(f,self.w.reshape(17*(d+2),channels,1,1),self.b.reshape(-1)).reshape(1,17,d+2,h,w)
        metric=logits[:,:,1].reshape(1,17,h*w).softmax(-1).reshape(1,17,h,w)
        prob=logits[:,:,2:].reshape(1,17,d*h*w).softmax(-1).reshape(1,17,d,h,w)
        xs=torch.linspace(0,1,w);ys=torch.linspace(0,1,h);zs=torch.linspace(0,1,d)
        c2=torch.stack([(prob.sum((2,3))*xs).sum(-1),(prob.sum((2,4))*ys).sum(-1)],-1)
        c3=torch.stack([(metric.sum(2)*xs).sum(-1),(metric.sum(3)*ys).sum(-1),(prob.sum((3,4))*zs).sum(-1)],-1)
        u=torch.nn.functional.softplus((logits[:,:,0]*prob.sum(2)).sum((2,3))+self.ub)+self.ub2
        last=(self.side-1)//self.stride*self.stride;offset=self.stride//2 if self.centered else 0
        return c2*last+offset,torch.cat([(c3[:,:,:2]*last+offset)*self.box/self.side,c3[:,:,2:]*self.box],-1),u

def crop_one(m,rgb,box):
    h,w=rgb.shape[:2];f=max(h,w)/(2*np.tan(np.deg2rad(55)/2))
    k=torch.tensor([[[f,0,w/2],[0,f,h/2],[0,0,1]]],dtype=torch.float32)
    x=(torch.from_numpy(rgb.copy()).permute(2,0,1)[None].float()/255).pow(2.2)
    crops,nk,r=m._get_crops(x,k,torch.zeros(1,5),torch.tensor([[0.,-1.,0.]]),
        torch.tensor(box[None]),torch.tensor([0]),torch.eye(3)[None],torch.ones(1),torch.tensor([.8]),1)
    return crops.reshape(1,3,384,384).contiguous(),nk.reshape(1,3,3),r.reshape(1,3,3)

def main():
    torch.set_num_threads(8);MOBILE.mkdir(exist_ok=True)
    m=load_quantized('cpu');weights=torch.load(OUT/'models/nlf-l-h36m17-query-weights.pt',weights_only=True)
    core=Core(m.crop_model,weights).eval()
    data=json.loads((OUT/'comparison-data.json').read_text(encoding='utf8'))
    meta=[]
    with torch.inference_mode():
        for side in ['A','B']:
            for i,t,rgb,coco,box in input_frames(side,data):
                if i%5 or (side=='B' and i not in [0,10,20,30,40,60,90,120]):continue
                x,k,r=crop_one(m,rgb,box)
                tag=f'{side}-{i:03d}'
                np.save(MOBILE/f'{tag}.npy',x.numpy());x.numpy().tofile(MOBILE/f'{tag}.bin')
                c2,c3,u=core(x)
                orig=m.crop_model.heatmap_head.decode_features_multi_same_weights(m.crop_model.get_features(x),weights,torch.zeros(1,dtype=torch.bool))
                assert max(float((a-b).abs().max()) for a,b in zip((c2,c3,u),orig))<.002
                ref,unc=m.crop_model.heatmap_head.reconstruct_absolute(c2,c3,u,k)
                raw=(ref@r)[0].numpy()/1000
                np.savez(MOBILE/f'{tag}-reference.npz',coords2d=c2.numpy(),coords3d=c3.numpy(),uncertainty=u.numpy(),K=k.numpy(),R=r.numpy(),raw=raw)
                meta.append({'tag':tag,'side':side,'frame':i,'calibration':side=='A'})
                print('crop',tag,flush=True)
        x=torch.from_numpy(np.load(MOBILE/'A-000.npy'))
        (MOBILE/'samples.json').write_text(json.dumps(meta,indent=2))
        print('Tracing',flush=True)
        traced=torch.jit.trace(core,x,check_trace=False)
        # Export a normal float graph; QDQ activation calibration follows separately.
        path=MOBILE/'nlf-l-core-fp32.onnx'
        torch.onnx.export(traced,x,str(path),opset_version=17,input_names=['image'],
            output_names=['coords2d','coords3d','uncertainty'],do_constant_folding=True)
        print('exported',path.stat().st_size,flush=True)
    (MOBILE/'samples.json').write_text(json.dumps(meta,indent=2))
if __name__=='__main__':main()
