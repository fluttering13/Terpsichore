"""Offline regression checks against the extractor and yt-dlp shipped in the APK."""
import importlib.util
import json
from pathlib import Path
import sys
import unittest

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'android/app/src/main/assets/platform_downloader'
sys.path.insert(0, str(ASSETS / 'yt-dlp'))
from yt_dlp import YoutubeDL
from yt_dlp.utils import ExtractorError

spec = importlib.util.spec_from_file_location(
    'threads_under_test', ASSETS / 'plugins/threads/yt_dlp_plugins/extractor/threads.py')
threads = importlib.util.module_from_spec(spec)
spec.loader.exec_module(threads)


class ThreadsTargetTest(unittest.TestCase):
    def extractor(self, posts, canonical=''):
        extractor = threads.ThreadsIE(YoutubeDL({'quiet': True}))
        webpage = '<script type="application/json">' + json.dumps(posts) + '</script>'
        if canonical:
            webpage += f'<meta property="og:url" content="{canonical}">'
        extractor._download_webpage = lambda *args, **kwargs: webpage
        return extractor

    @staticmethod
    def post(code):
        return {'code': code, 'original_width': 3840, 'original_height': 2160,
                'video_versions': [{'type': 101, 'url': f'https://cdn.example/{code}.mp4'}]}

    def test_selects_target_instead_of_first_recommended_video(self):
        extractor = self.extractor([self.post('recommendation'), self.post('target')])
        result = extractor._real_extract('https://www.threads.com/@dancer/post/target')
        self.assertEqual(result['id'], 'target')
        self.assertEqual(result['formats'][0]['url'], 'https://cdn.example/target.mp4')
        self.assertIsNone(result['formats'][0]['width'])
        self.assertIsNone(result['formats'][0]['height'])

    def test_missing_target_does_not_download_recommendation(self):
        extractor = self.extractor([self.post('recommendation')])
        with self.assertRaises(ExtractorError):
            extractor._real_extract('https://www.threads.com/@dancer/post/missing')

    def test_ambiguous_share_link_is_rejected(self):
        extractor = self.extractor([self.post('recommendation')])
        with self.assertRaises(ExtractorError):
            extractor._real_extract('https://www.threads.com/share/unknown')

    def test_share_link_uses_canonical_target(self):
        extractor = self.extractor([self.post('recommendation'), self.post('target')],
                                   'https://www.threads.com/@dancer/post/target')
        self.assertEqual(extractor._real_extract('https://www.threads.com/share/abc')['id'], 'target')


if __name__ == '__main__':
    unittest.main()
