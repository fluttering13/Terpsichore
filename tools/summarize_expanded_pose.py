"""Generate a review index and machine-readable timing/alignment tables."""
import csv
import html
import json
from pathlib import Path

ROOT=Path('build/pose-expanded')

def main():
    report=json.loads((ROOT/'report.json').read_text())
    report['visual_reviews']=[dict(date='2026-09-18',case='choreo',model=name,
        observation='Source B 1.5s: foreground/cross-person pose; 3s: intended subject. Not a valid subject-consistent alignment.',
        type='manual_spot_check_not_exhaustive') for name in ['blazepose','movenet-lightning','movenet-thunder']]
    (ROOT/'report.json').write_text(json.dumps(report,indent=2))
    fields=['model','case','mode','clip','pose_calls','pose_p50_ms','pose_p95_ms',
            'detector_p50_ms','pipeline_p50_ms','pipeline_p95_ms','feature_frames',
            'sample_frames','b_start','b_rate','mapping_error_seconds','warning','visual_review']
    rows=[]
    for r in report['results']:
        prediction=r['result'] or {}
        for i,side in enumerate(['a','b']):
            t=r['timings'][side];p=t['pose_call'] or {};d=t['detector_call'] or {};f=t['pipeline_frame']
            rows.append(dict(model=r['model'],case=r['case'],mode=r['mode'],clip=side,
                pose_calls=p.get('n',0),pose_p50_ms=p.get('p50_ms'),pose_p95_ms=p.get('p95_ms'),
                detector_p50_ms=d.get('p50_ms'),pipeline_p50_ms=f['p50_ms'],pipeline_p95_ms=f['p95_ms'],
                feature_frames=r['feature_frames'][i][0],sample_frames=r['feature_frames'][i][1],
                b_start=prediction.get('b_start'),b_rate=prediction.get('b_rate'),
                mapping_error_seconds=prediction.get('mean_mapping_error_b_source_seconds'),
                warning=prediction.get('warning','no_valid_alignment'),
                visual_review='subject_contamination_observed' if r['case']=='choreo' and r['model'] in ['blazepose','movenet-lightning','movenet-thunder'] else 'not_exhaustively_reviewed'))
    with (ROOT/'measurements.csv').open('w',newline='',encoding='utf-8-sig') as output:
        writer=csv.DictWriter(output,fieldnames=fields);writer.writeheader();writer.writerows(rows)
    def fmt(value):return '-' if value is None else f'{value:.1f}'
    body=['<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width">',
        '<title>Terpsichore Pose 模型實驗</title>',
        '<style>body{font:16px sans-serif;max-width:1100px;margin:24px auto;padding:0 16px;background:#171717;color:#eee}a{color:#8bc9ff}td,th{padding:8px;border-bottom:1px solid #555;text-align:left}table{border-collapse:collapse}li{margin:12px 0}</style>',
        '<h1>Pose 模型實驗</h1><p>桌面 CPU：i9-14900F / ONNX Runtime 1.30 / 2 threads。不是手機速度。</p>',
        '<p>影片皆無音訊、無時間平滑。骨架比較以半速播放；alignment comparison 每段代表一個模型，左側手調、右側模型結果。骨架信心與可用幀數不是準確率。</p>',
        '<p><strong>人工抽查警告：</strong>排舞 B 的 1.5 秒，BlazePose 抓到前景人物，MoveNet 出現跨人骨架；3 秒時回到主體。這三個方案的排舞結果受人物混淆影響，不能當作有效的主體對齊；這不是完整逐幀 ID 審核。</p>',
        '<h2>速度：排舞 B 影片（原方向）</h2><p>Top-down 單次是每個人物；YOLO/LitePose 單次已含全圖偵測。Pipeline 包含偵測、最多五人姿勢、前後處理，但不含後續追蹤選擇與對齊搜尋。</p>',
        '<table><tr><th>模型</th><th>單次 p50 ms</th><th>單次 p95 ms</th><th>偵測 p50 ms</th><th>Pipeline p50 ms/幀</th></tr>']
    for r in rows:
        if r['case']=='choreo' and r['clip']=='b' and r['mode']=='raw':
            body.append('<tr><td>'+html.escape(r['model'])+'</td>'+''.join('<td>'+fmt(r[k])+'</td>' for k in ['pose_p50_ms','pose_p95_ms','detector_p50_ms','pipeline_p50_ms'])+'</tr>')
    body.append('</table><h2>對齊結果</h2><p>Airflare 手調 B 起點 0s / 0.9x；排舞手調 1.2s / 1x。誤差是平均 B 來源時間映射差，不是骨架準確率。邊界解不可視為可靠方案。</p><table><tr><th>模型</th><th>案例／模式</th><th>B 起點</th><th>B 速度</th><th>映射誤差秒</th><th>備註</th></tr>')
    for r in rows:
        if r['clip']!='b':continue
        body.append('<tr>'+''.join('<td>'+html.escape(str(v if v is not None else '-'))+'</td>' for v in [r['model'],r['case']+'/'+r['mode'],r['b_start'],r['b_rate'],r['mapping_error_seconds'],r['warning']])+'</tr>')
    body.append('</table><h2>影片</h2><p>diverse：ViTPose、MoveNet Lightning／Thunder、BlazePose、HRNet。standard：RTMPose、YOLO、LitePose。raw：原方向；rot4：四方向推論。</p><ul>')
    for p in sorted(ROOT.glob('*.mp4')):body.append(f'<li><a href="{html.escape(p.name)}">{html.escape(p.name)}</a></li>')
    body.append('</ul><p><a href="measurements.csv">完整測量 CSV</a> | <a href="report.json">原始報告 JSON</a></p>')
    (ROOT/'index.html').write_text('\n'.join(body),encoding='utf-8')
    print('Generated',ROOT/'index.html',flush=True)

if __name__=='__main__':main()
