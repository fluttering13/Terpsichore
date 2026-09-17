"""Fully decode/count every review video and record delivery checksums."""
import hashlib
import json
import math
import subprocess
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT=Path('build/pose-expanded')

def verify(job):
    path,frames,width,height=job
    raw=subprocess.check_output(['ffprobe','-v','error','-threads','2','-select_streams','v:0',
        '-count_frames','-show_entries','stream=codec_name,pix_fmt,width,height,nb_read_frames,avg_frame_rate',
        '-of','json',str(path)],text=True)
    stream=json.loads(raw)['streams'][0]
    assert stream['codec_name']=='h264' and stream['pix_fmt']=='yuv420p',path
    assert stream['width']==width and stream['height']==height,path
    assert int(stream['nb_read_frames'])==frames,(path,stream,frames)
    assert stream['avg_frame_rate']=='24/1',path
    print('Verified',path.name,frames,'frames',flush=True)
    return dict(file=path.name,bytes=path.stat().st_size,sha256=hashlib.sha256(path.read_bytes()).hexdigest(),**stream)

if __name__=='__main__':
    report=json.loads((ROOT/'report.json').read_text());assert len(report['results'])==45
    jobs=[]
    for case in report['cases']:
        for mode in (['raw','rot4'] if case['name']=='airflare' else ['raw']):
            for group,count in [('standard',10),('diverse',5)]:
                for side in ['a','b']:
                    jobs.append((ROOT/f'{case["name"]}-{side}-{mode}-{group}-models.mp4',
                        math.ceil(case[side+'_end']/.5*24),1600,1120 if group=='standard' else 560))
                jobs.append((ROOT/f'{case["name"]}-{mode}-{group}-alignment-comparison.mp4',
                    math.ceil(case['a_end']/case['a_rate']*24)*count,1280,560))
    with ThreadPoolExecutor(max_workers=3) as pool:manifest=list(pool.map(verify,jobs))
    assert len(manifest)==18
    (ROOT/'video-manifest.json').write_text(json.dumps(manifest,indent=2))
