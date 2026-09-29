#!/usr/bin/env python3
"""Tests for the independent comparison measurements, not for the renderer."""
import unittest
from PIL import Image,ImageDraw
from compare_live import metrics,bbox
class ComparisonTests(unittest.TestCase):
    def test_identical(self):
        im=Image.new('RGBA',(4,4),(80,90,100,255));self.assertEqual(metrics(im,im)['rgbMAE'],0)
    def test_transparent_rgb_is_ignored(self):
        a=Image.new('RGBA',(4,4),(255,0,0,0));b=Image.new('RGBA',(4,4),(0,255,255,0));self.assertEqual(metrics(a,b)['rgbMAE'],0)
    def test_one_level_error(self):
        a=Image.new('RGB',(4,4),(20,20,20));b=Image.new('RGB',(4,4),(21,21,21));self.assertEqual(metrics(a,b)['rgbMAE'],1)
    def test_dimensions_fail(self):
        with self.assertRaises(ValueError):metrics(Image.new('RGB',(4,4)),Image.new('RGB',(4,5)))
    def test_motion_bounds(self):
        im=Image.new('RGB',(64,48),(10,10,10));ImageDraw.Draw(im).rectangle((20,12,39,31),fill=(200,200,200));self.assertEqual(bbox(im),(20,12,40,32))
if __name__=='__main__':unittest.main()
