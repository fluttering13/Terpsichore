"""Generate small JVM regression fixtures from the original NLF TorchScript math."""
import struct
from pathlib import Path
import numpy as np
import torch
from quantize_nlf import load_quantized

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'android/app/src/test/resources/pose3d'

def write(path, *values):
    with path.open('wb') as f:
        for v in values:
            f.write(np.asarray(v, dtype='>f4').tobytes())

def main():
    DEST.mkdir(parents=True, exist_ok=True)
    m = load_quantized('cpu')
    torch.set_num_threads(4)
    with torch.inference_mode():
        for tag in ['A-000','B-030']:
            v = np.load(ROOT / f'build/pose3d-poc/models/nlf-mobile/{tag}-reference.npz')
            c2,c3,u,k,r = [torch.from_numpy(v[n]) for n in ['coords2d','coords3d','uncertainty','K','R']]
            absolute,_ = m.crop_model.heatmap_head.reconstruct_absolute(c2,c3,u,k)
            write(DEST / (tag+'.bin'), c2,c3,u,k[0,0,0],absolute/1000)
        w,h = 801,601
        yy,xx = np.mgrid[:h,:w]
        rgb = np.stack([(xx*3+yy)%256,(xx+yy*2)%256,(xx*7+yy*5)%256],-1).astype(np.uint8)
        linear = (torch.from_numpy(rgb).permute(2,0,1).float()[None]/255).pow(2.2)
        f = max(w,h)/(2*np.tan(np.deg2rad(55)/2))
        k = torch.tensor([[[f,0,(w-1)/2],[0,f,(h-1)/2],[0,0,1]]],dtype=torch.float32)
        angles = -torch.deg2rad(torch.linspace(-25,25,5))
        r = torch.eye(3).repeat(5,1,1)
        r[:,0,0] = r[:,1,1] = angles.cos()
        r[:,0,1] = -angles.sin(); r[:,1,0] = angles.sin()
        r[[1,3],0] *= -1
        for index,box in enumerate([[83.,41.,630.,510.],[-35.,110.,390.,360.]]):
            crops,nk,rot = m._get_crops(linear,k,torch.zeros(1,5),torch.tensor([[0.,-1.,0.]]),
                torch.tensor([box]),torch.tensor([0]),r,torch.tensor([.8,.9,1.,1.05,1.1]),torch.linspace(.6,1,5),1)
            # Fixed 40 pixel probes per augmentation across all three channels.
            probes = [(i*71%384,i*113%384,i%3) for i in range(40)]
            sampled = [[crops[a,0,c,y,x] for x,y,c in probes] for a in range(5)]
            write(DEST / f'crop-{index}.bin',box,nk[:,0,0,0],rot[:,0],sampled)
    print('Wrote original-model geometry fixtures:',DEST)

if __name__ == '__main__': main()
