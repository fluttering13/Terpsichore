"""Current app weights only: MoveNet Thunder. No separate person detector."""
import shutil
from pathlib import Path
from download_diverse_pose import download

SOURCES=[
 ('movenet-thunder','Xenova/movenet-singlepose-thunder','38296077a99667cdad67af5096ce7eeb9b327453','onnx/model.onnx'),
]
if __name__=='__main__':
    Path('build/pose-candidates').mkdir(parents=True,exist_ok=True)
    for source in SOURCES:
        download(source)
        shutil.copy2(Path('build/pose-candidates')/(source[0]+'.onnx'),Path('asset/models')/(source[0]+'.onnx'))
