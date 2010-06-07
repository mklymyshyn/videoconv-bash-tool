import random
import os
import string

import unittest
from test import test_support

from videoconv import *

TEST_ROOT = os.path.dirname(os.path.realpath(__file__))
VIDEO_PATH = os.path.realpath(TEST_ROOT + '/../../tests/videos')
TOOL_PATH = "%s/convert-video.sh" % os.path.realpath(TEST_ROOT + '/../../bin/')

"""
Error1: 
-c -e -i /Users/gabonsky/Projects/Elearning/videoconv/tests/videos/mov160x120-low.mov -o /Users/gabonsky/Projects/Elearning/videoconv/tests/videos/result/taAz9gXoz2.mp4 -q 77 -p 320x240 -r -t mp4


-c -e -i /Users/gabonsky/Projects/Elearning/videoconv/tests/videos/wmv640x480-sd.wmv -o /Users/gabonsky/Projects/Elearning/videoconv/tests/videos/result/gaEz2gNoT8.mp4 -q 79 -p 320x240 -r -t mp4
"""
class TestVideoConv(unittest.TestCase):

    # Only use setUp() and tearDown() if necessary
    
    def setUp(self):
        self.ids = []
        self.videos = os.listdir(VIDEO_PATH)
        
        self.conv = VideoconvWrapper(tool_path = TOOL_PATH, debug = True)

        #info = conv.info()
        #print "Info keys: %s" % ", ".join(info.keys())
        #print "Duration: %s" % info.duration

        self.conv.options({
            't' : 'mp4', # type of encoding
            'e' : '', # two-pass encoding
            'r' : '', # using delayed conversion
            'c' : '' # generate thumbnails after conversion
        })

        #conv.convert()
        
        #conv.unregister()

    def tearDown(self):
        pass

    def _generate_id(self):
        id = random.choice(range(1, 100))
        while id in self.ids:
            id = random.choice(range(1, 100))
            
        return id
        
    def test_video_info(self):
        for video in self.videos:
            path_to_source = "%s/%s" % (VIDEO_PATH, video)
            
            self.conv.set_video(path_to_source)
            
            print "--" * 40
            info = self.conv.info()
            print "Info keys: %s" % ", ".join(info.keys())
            for key in info.keys():
                print "%s = %s" % (
                key, getattr(info, key)
                )
        
    def test_webformat_conversion(self):
        # Test feature one.
        for video in self.videos:
            path_to_source = "%s/%s" % (VIDEO_PATH, video)
            path_to_dst = "%s/result/%s.mp4" % (
            VIDEO_PATH, 
            "".join([random.choice(string.letters + string.digits) for i in range(10)])
            )
            
            id = self._generate_id()
            
            self.conv.set_video(path_to_source)
            self.conv.set_destination_video(path_to_dst)
            
            self.conv.option('q', id)
            self.conv.option('p', '320x240')
            
            print "Conversion ID:%d : from %s to %s" % (
            id, path_to_source, path_to_dst
            )
            self.conv.convert()


# run tests
def test_main():
    test_support.run_unittest(TestVideoConv)

if __name__ == '__main__':
    test_main()