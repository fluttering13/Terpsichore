"""Local image-based Airflare trials; no smoothing or generated occlusion filling.

Native video frames are used. MoveNet only supplies the target bounding box to
NLF/MeTRAbs, and remains the unchanged 2D overlay in the comparison viewer.
Raw camera coordinates are retained; estimated camera scale is not ground truth.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import sys
import subprocess
import time

import cv2
import numpy as np
import torch
import torchvision

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'build/pose3d-poc'

def input_frames(side,data):
    track=data['variants']['movenet'][side]
    oldtimes=np.asarray(track['times']);old=np.asarray(track['coco'])
    cap=cv2.VideoCapture(str(OUT/f'{side}.mp4'));fps=cap.get(cv2.CAP_PROP_FPS)
    i=0
    while True:
        ok,frame=cap.read()
        if not ok:break
        t=i/fps
        coco=np.stack([np.interp(t,oldtimes,old[:,j,d]) for j in range(17) for d in range(3)]).reshape(17,3)
        xy=coco[coco[:,2]>.2,:2]
        if len(xy)<4:xy=coco[:,:2]
        lo=xy.min(0);hi=xy.max(0);margin=np.maximum((hi-lo)*.18,25)
        lo=np.maximum(lo-margin,0);hi=np.minimum(hi+margin,[frame.shape[1],frame.shape[0]])
        box=np.r_[lo,hi-lo].astype(np.float32)
        yield i,t,cv2.cvtColor(frame,cv2.COLOR_BGR2RGB),coco,box
        i+=1
    cap.release()

def load_nlf(small=False,quantized=False,device='cuda'):
    path=OUT/'models'/('nlf_s_multi_0.2.2.torchscript' if small else 'nlf_l_multi_0.3.2.patch4.torchscript')
    if quantized:
        from quantize_nlf import load_quantized,TARGET
        path=TARGET;model=load_quantized(device)
    else:model=torch.jit.load(str(path),map_location='cpu').eval().to(device)
    with torch.inference_mode(),torch.device(device):
        locs=model.crop_model.canonical_locs()
        inds=model.per_skeleton_indices['h36m_17'].long().to(device)
        weights=model.get_weights_for_canonical_points(locs[inds])
        if device=='cpu':weights={k:v.float() for k,v in weights.items()}
    def infer(rgb,box,coco):
        x=torch.from_numpy(rgb.copy()).permute(2,0,1)[None].to(device)
        with torch.inference_mode(),torch.device(device):
            result=model.estimate_poses_batched(x,[torch.tensor(box[None],device=device)],weights,num_aug=5)
        return result['poses3d'][0][0].cpu().numpy()/1000, {k:v[0][0].cpu().numpy() for k,v in result.items() if k!='boxes'}
    return infer,path,{'label':('NLF-S v0.2.2' if small else 'NLF-L v0.3.2')+' · 影像直接重建','source':'https://github.com/isarandi/nlf','joints':model.per_skeleton_joint_names['h36m_17'],'num_aug':5}

def load_metrabs():
    import types
    import pickle
    import torchvision.models._utils
    os.environ['DATA_ROOT']=str(OUT/'models')
    repo=OUT/'metrabs';sys.path.insert(0,str(repo))
    # This removed torchvision alias only wraps deprecated download URLs.
    if not hasattr(torchvision.models._utils,'_ModelURLs'):
        torchvision.models._utils._ModelURLs=dict
    # Dataset training utilities are unused during pretrained inference.
    src=repo/'metrabs_pytorch/util.py'
    code=src.read_text().replace('import posepile.datasets3d as ds3d','# unused training dataset import')
    util=types.ModuleType('metrabs_pytorch.util');util.__file__=str(src)
    sys.modules[util.__name__]=util;exec(compile(code,str(src),'exec'),util.__dict__)
    from posepile.joint_info import JointInfo
    from metrabs_pytorch.backbones import efficientnet
    from metrabs_pytorch.models.metrabs import Metrabs
    from metrabs_pytorch.multiperson import multiperson_model,person_detector
    folder=OUT/'models/metrabs_eff2l_384px_800k_28ds_pytorch'
    cfg=util.get_config(str(folder/'config.yaml'))
    ji=np.load(folder/'joint_info.npz')
    backbone=efficientnet.efficientnet_v2_l()
    crop=Metrabs(torch.nn.Sequential(efficientnet.PreprocLayer(),backbone.features),JointInfo(ji['joint_names'],ji['joint_edges'])).eval()
    with torch.inference_mode():crop((torch.zeros(1,3,cfg.proc_side,cfg.proc_side),torch.eye(3)[None]))
    crop.load_state_dict(torch.load(folder/'ckpt.pt',map_location='cpu',weights_only=True),strict=True)
    # Target boxes come from existing MoveNet tracks, not an extra detector.
    class UnusedDetector(torch.nn.Module):
        def forward(self,*args,**kwargs):raise RuntimeError('Use provided target boxes')
    person_detector.PersonDetector=UnusedDetector
    with (folder/'skeleton_infos.pkl').open('rb') as f:infos=pickle.load(f)
    with torch.device('cuda'):
        model=multiperson_model.Pose3dEstimator(crop.cuda(),infos,np.load(folder/'joint_transform_matrix.npy')).cuda().eval()
    skeleton='h36m_17'
    def infer(rgb,box,coco):
        x=torch.from_numpy(rgb.copy()).permute(2,0,1)[None].cuda()
        with torch.inference_mode(),torch.device('cuda'):
            result=model._estimate_poses_batched(x,[torch.tensor(np.r_[box,1.][None],device='cuda',dtype=torch.float32)],
                intrinsic_matrix=torch.full((1,3,3),-1.),distortion_coeffs=torch.zeros(1,5),
                extrinsic_matrix=torch.eye(4)[None],world_up_vector=torch.tensor([0.,-1.,0.]),
                skeleton=skeleton,num_aug=5,default_fov_degrees=55,internal_batch_size=64,
                antialias_factor=1,average_aug=True,suppress_implausible_poses=False)
        return result['poses3d'][0][0].cpu().numpy()/1000,{'poses2d':result['poses2d'][0][0].cpu().numpy()}
    return infer,folder/'ckpt.pt',{'label':'MeTRAbs · 影像直接重建','source':'https://github.com/isarandi/metrabs',
        'joints':list(infos[skeleton]['names']),'num_aug':5,'compatibility':'Unused training import omitted; deprecated URL dict alias; external MoveNet boxes'}

def load_multihmr():
    from PIL import Image,ImageOps
    from argparse import Namespace
    import types
    sys.path.insert(0,str(OUT/'multi-hmr'))
    src=OUT/'multi-hmr/multi_hmr_anny/multi_hmr.py'
    code=src.read_text(encoding='utf8')
    unused="'blendshape_coeffs': output['blendshape_coeffs'],"
    assert unused in code
    # Anny 0.6 no longer returns this training-only value. It is not used in
    # the inference persons list; removing its dictionary access changes no math.
    code=code.replace(unused,'# unused training-only blendshape output omitted')
    module=types.ModuleType('multihmr_anny_compat')
    exec(compile(code,str(src),'exec'),module.__dict__)
    Multi_HMR=module.Multi_HMR
    from utils.image import normalize_rgb
    path=OUT/'models/multiHMR_672_L_anny.pt'
    with torch.serialization.safe_globals([Namespace]):
        ckpt=torch.load(path,map_location='cpu',weights_only=True)
    hub_load=torch.hub.load
    def local_dino(repo,model,*args,**kwargs):
        if repo=='facebookresearch/dinov2':
            return hub_load(str(OUT/'dinov2'),model,*args,source='local',**kwargs)
        return hub_load(repo,model,*args,**kwargs)
    torch.hub.load=local_dino
    kwargs=vars(ckpt['args']).copy()
    # Full backbone weights are already in the model checkpoint; strict load
    # below verifies every parameter, so no separate ImageNet initialization.
    kwargs['pretrained_backbone']=False
    try:model=Multi_HMR(**kwargs).cuda().eval()
    finally:torch.hub.load=hub_load
    model.load_state_dict(ckpt['model_state_dict'],strict=True)
    names=model.body_model.bone_labels
    # Anny bone origins are used, not bone tips. Head-top is unavailable;
    # its viewer point is a head-segment proxy and excluded from torso metrics.
    selected=['root','upperleg01.R','lowerleg01.R','foot.R','upperleg01.L','lowerleg01.L','foot.L',
              'spine03','neck01','head','head','upperarm01.L','lowerarm01.L','wrist.L',
              'upperarm01.R','lowerarm01.R','wrist.R']
    inds=[names.index(n) for n in selected]
    size=int(model.img_size)
    def infer(rgb,box,coco):
        image=Image.fromarray(rgb)
        contained=ImageOps.contain(image,(size,size));sx=contained.width/image.width;sy=contained.height/image.height
        offset=np.array([(size-contained.width)//2,(size-contained.height)//2])
        padded=ImageOps.pad(contained,(size,size))
        x=torch.from_numpy(normalize_rgb(np.asarray(padded))).unsqueeze(0).cuda()
        def overlap(h):
            p=(h['j2d'][inds].float().cpu().numpy()-offset)/[sx,sy]
            lo=p.min(0);hi=p.max(0)
            intersection=np.maximum(np.minimum(hi,box[:2]+box[2:])-np.maximum(lo,box[:2]),0).prod()
            return intersection/max((hi-lo).prod()+box[2:].prod()-intersection,1e-8)
        with torch.inference_mode(),torch.autocast('cuda',enabled=True):
            humans=model(x,is_training=False,det_thresh=.3,nms_kernel_size=3,K=None)
            fallback=not isinstance(humans,list) or not humans or max(overlap(h) for h in humans)<.2
            if fallback:
                # The official forward supports external head-centred tokens.
                head=coco[0,:2]*[sx,sy]+offset
                cell=np.clip(np.floor(head/model.patch_size).astype(int),0,size//model.patch_size-1)
                idx=tuple(torch.tensor([int(v)],device='cuda') for v in [0,cell[1],cell[0]])
                humans=model(x,is_training=False,idx=idx,det_thresh=.3,nms_kernel_size=3,K=None)
        if not isinstance(humans,list) or not humans:raise RuntimeError('No person returned even with target hint')
        # Reject background bystanders: their small projected box has low IoU
        # with the existing dancer track even if their centre is nearby.
        h=max(humans,key=overlap)
        joints=h['j3d'].float().cpu().numpy()
        mapped=joints[inds].copy();mapped[10]=mapped[9]+.5*(mapped[9]-mapped[8])
        return mapped,{'joints3d_full':joints,'rotmat':h['rotmat'].float().cpu().numpy(),
            'poses2d':(h['j2d'][inds].float().cpu().numpy()-offset)/[sx,sy],
            'K':h['K'].float().cpu().numpy(),'head_hint_fallback':np.array(fallback)}
    return infer,path,{'label':'Multi-HMR Anny · 含 2D 頭部提示補救','source':'https://github.com/naver/multi-hmr',
        'joints':selected,'all_joints':names,'head_proxy':'Display joint 10 extrapolates head + 0.5*(head-neck01); not an estimated anatomical landmark',
        'compatibility':'Anny 0.6: unused training-only blendshape output access omitted; full strict checkpoint loading',
        'intrinsics':'Predicted by model','target_matching':'Maximum projected major-joint bbox IoU against MoveNet target; minimum 0.2',
        'fallback':'When no target detection has IoU >= 0.2, use recorded MoveNet nose as external head token; per-frame flag exported'}

def main():
    parser=argparse.ArgumentParser();parser.add_argument('model',choices=['nlf','nlf-s','nlf-int8','metrabs','multihmr-anny'])
    parser.add_argument('--limit',type=int,default=0);args=parser.parse_args()
    torch.set_num_threads(4);torch.manual_seed(0)
    data=json.loads((OUT/'comparison-data.json').read_text(encoding='utf8'))
    print('Loading',args.model,flush=True)
    if args.model in ['nlf','nlf-s','nlf-int8']:
        torch._C._set_graph_executor_optimize(False)
        infer,path,meta=load_nlf(args.model=='nlf-s',args.model=='nlf-int8')
        if args.model=='nlf-int8':meta['label']='NLF-L · INT8 權重／浮點運算'
    elif args.model=='metrabs':infer,path,meta=load_metrabs()
    else:infer,path,meta=load_multihmr()
    meta['checkpoint_sha256']=hashlib.sha256(path.read_bytes()).hexdigest()
    meta['camera']='Uncalibrated camera coordinates; no world/ground registration'
    meta['temporal_smoothing']=False
    meta['input']='Native RGB frames; MoveNet bounding box for NLF/MeTRAbs only'
    meta['torch_version']=str(torch.__version__)
    meta['device']=torch.cuda.get_device_name()
    if args.model in ['metrabs','multihmr-anny']:
        repo=OUT/('metrabs' if args.model=='metrabs' else 'multi-hmr')
        meta['code_revision']=subprocess.check_output(['git','-C',str(repo),'rev-parse','HEAD'],text=True).strip()
    print('Loaded',args.model,flush=True)
    for side in ['A','B']:
        poses=[];times=[];cocos=[];extras=[];start=time.perf_counter()
        for i,t,rgb,coco,box in input_frames(side,data):
            if args.limit and i>=args.limit:break
            raw,extra=infer(rgb,box,coco)
            assert raw.shape==(17,3) and np.isfinite(raw).all(),(side,i,raw)
            poses.append(raw);times.append(t);cocos.append(coco);extras.append(extra)
            if i%10==0:print(args.model,side,i,'frames',round(time.perf_counter()-start,1),'sec',flush=True)
        payload={'raw':np.asarray(poses),'times':np.asarray(times),'coco2d':np.asarray(cocos)}
        for k in extras[0]:
            try:payload['model_'+k]=np.stack([x[k] for x in extras])
            except (ValueError,KeyError):pass
        prefix='smoke-' if args.limit else ''
        np.savez_compressed(OUT/f'{prefix}{args.model}-{side}.npz',**payload)
        print('Saved',side,len(times),'frames',flush=True)
    (OUT/f'{args.model}-metadata.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2),encoding='utf8')

if __name__=='__main__':main()
