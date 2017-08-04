# encoding: utf-8
'''
Created on 2017年7月24日

@author: zzlzhang@cn.ibm.com
'''

from __future__ import print_function
import sys

__all__ = [
    'print_msg',
    'print_err'
]

def print_headder_msg(*args, **kwargs):
    print("******** {:s} ********".format(*args), **kwargs)
    sys.stdout.flush()

def print_msg(*args, **kwargs):
    print(*args, **kwargs)
    sys.stdout.flush()

def print_err(*args, **kwargs):
    print(*args, file=sys.stderr, **kwargs)