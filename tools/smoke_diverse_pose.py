"""Single-frame decoder sanity check; these timings are not benchmark results."""
import cv2
import numpy as np
from pathlib import Path
import diverse_pose_adapters as d
from benchmark_pose_candidates import load,yolo,area
from render_expanded_pose import tile

def main():
    target=Path('build/pose-expanded');target.mkdir(parents=True,exist_ok=True)
    cap=cv2.VideoCapture('build/manual-choreo-a.mp4');cap.set(cv2.CAP_PROP_POS_MSEC,1000)
    ok,image=cap.read();cap.release();assert ok
    detector,_=load('yolo11s-pose');people,_=yolo(detector,image)
    box=max(people,key=lambda p:area(p[0]))[0]
    tiles=[]
    for name in d.NAMES:
        model,_=d.load(name)
        print(name,[(i.name,i.shape,i.type) for i in model.get_inputs()],flush=True)
        if name=='blazepose':
            detector,_=d.load('blazepose-detector');aux,_=d.blaze_detect(detector,image)
            poses=[d.blaze_pose(model,image,p)[0] for p in aux]
            person=next((p for p in poses if p is not None),None)
        else:
            points,_=(d.VitPose() if name=='vitpose-small' else (d.hrnet if name=='hrnet-w32' else d.movenet))(model,image,box)
            person=(box,points)
        selected=None if person is None else dict(points=person[1].tolist())
        print(name,'mean confidence',np.mean(person[1][:,2]) if person else None,flush=True)
        tiles.append(tile(image,[dict(t=1.,person=selected)],1.,name,'Decoder smoke check'))
    cv2.imwrite(str(target/'diverse-decoder-smoke.jpg'),np.hstack(tiles))

if __name__=='__main__':main()
