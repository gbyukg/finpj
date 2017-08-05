# encoding: utf-8
'''
Created on 2017年7月24日

@author: zzlzhang@cn.ibm.com
'''

from __future__ import print_function
from collections import namedtuple
import sys

__all__ = [
    'print_msg',
    'print_err',
    'InstallFlag'
]

# 'package git restore_install full_install init_db as_base_db data_loader avl ut independent_es qrr debug'
# 'source_from install_method init_db as_base_db data_loader avl ut independent_es qrr debug'
InstallFlag = namedtuple(
    'InstallFlag',
    'source_from_package source_from_git restore_install full_install init_db as_base_db data_loader avl ut independent_es qrr debug'
)

def print_header_msg(*args, **kwargs):
    print("******** {:s} ********".format(*args), **kwargs)
    sys.stdout.flush()

def print_msg(*args, **kwargs):
    print(*args, **kwargs)
    sys.stdout.flush()

def print_err(*args, **kwargs):
    print(*args, file=sys.stderr, **kwargs)