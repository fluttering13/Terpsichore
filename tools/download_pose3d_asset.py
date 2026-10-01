"""Download a public model asset in resumable, verified HTTP ranges."""
import argparse
import concurrent.futures
from pathlib import Path
import time
import requests
import os

def main():
    p=argparse.ArgumentParser()
    p.add_argument('url');p.add_argument('destination');p.add_argument('--workers',type=int,default=8)
    p.add_argument('--pipeline',type=int,default=1)
    a=p.parse_args();dest=Path(a.destination);dest.parent.mkdir(parents=True,exist_ok=True)
    headers={'Authorization':'Bearer '+os.environ['HF_TOKEN']} if os.environ.get('HF_TOKEN') else {}
    r=requests.head(a.url,headers=headers,allow_redirects=True,timeout=60);r.raise_for_status()
    size=int(r.headers['Content-Length']);url=r.url
    if dest.exists() and dest.stat().st_size==size:return
    chunk=(size+a.workers-1)//a.workers
    def fetch(i):
        start=i*chunk;end=min(size,start+chunk)-1
        path=dest.with_name(dest.name+f'.range{i}')
        failures=0
        while True:
            have=path.stat().st_size if path.exists() else 0
            if have==end-start+1:
                print(f'part {i+1}/{a.workers} complete',flush=True);return path
            try:
                if a.pipeline>1:
                    ranges=[(s,min(end,s+8*1024*1024-1)) for s in range(start+have,min(end+1,start+have+a.pipeline*8*1024*1024),8*1024*1024)]
                    def block(bounds):
                        lo,hi=bounds
                        res=requests.get(url,headers={'Range':f'bytes={lo}-{hi}'},timeout=90)
                        res.raise_for_status()
                        assert res.status_code==206 and res.headers['Content-Range']==f'bytes {lo}-{hi}/{size}'
                        assert len(res.content)==hi-lo+1
                        return res.content
                    with concurrent.futures.ThreadPoolExecutor(max_workers=a.pipeline) as inner:
                        chunks=list(inner.map(block,ranges))
                    with path.open('ab') as f:
                        for content in chunks:f.write(content)
                    failures=0
                    continue
                request_end=min(end,start+have+8*1024*1024-1)
                with requests.get(url,headers={'Range':f'bytes={start+have}-{request_end}'},stream=True,timeout=90) as res:
                    res.raise_for_status()
                    assert res.status_code==206, 'Server did not honor byte range'
                    assert res.headers['Content-Range']==f'bytes {start+have}-{request_end}/{size}'
                    with path.open('ab') as f:
                        for c in res.iter_content(1024*1024):f.write(c)
                assert path.stat().st_size==request_end-start+1
                failures=0
            except Exception:
                failures+=1
                if failures==6:raise
                time.sleep(2)
    with concurrent.futures.ThreadPoolExecutor(max_workers=a.workers) as ex:
        paths=list(ex.map(fetch,range(a.workers)))
    temp=dest.with_name(dest.name+'.assembling')
    with temp.open('wb') as f:
        for path in paths:
            with path.open('rb') as part:
                while c:=part.read(1024*1024):f.write(c)
    assert temp.stat().st_size==size
    temp.replace(dest)
    for path in paths:path.unlink()
    print(f'Complete: {dest} ({size} bytes)',flush=True)

if __name__=='__main__':main()
