# encoding: utf-8
'''
Created on 2017年7月24日

@author: zzlzhang@cn.ibm.com
'''
import os
import functools
from sys import modules as os_modules

__all__ = [
    'run_script',
    'installHooks'
]


def run_script(func_name, *args, **kvargs):
    cmd = "{}/install_hook.sh {} {}".format(
        os_modules['__main__'].sys.path[0],
        func_name,
        kvargs.get('cus_param', '')
    )

    pid = os.fork()
    if pid == 0:
        os.execlp("sh", 'sh', '-c', cmd)
    try:
        pid, status = os.wait()
        # 低 8 位用来存储信号信息, 高 8 位才是退出位
        if status >> 0x8 != 0:
            err_msg = "[install_hook {0:s}] error. Exit code: [{1:s}]".format(func_name, str(status >> 0x8))
            raise OSError(err_msg)
    except KeyboardInterrupt as e:
        raise KeyboardInterrupt("Hook function [{}] was interrupted: {}".format(func_name, e))


def installHooks(hook_type):
    def decorator(func):
        @functools.wraps(func)
        def wrapper(*args, **kvargs):
            # before hook
            run_script('before_' + hook_type, *args, **kvargs)
            func(*args, **kvargs)

            # after hook
            run_script('after_' + hook_type, *args, **kvargs)
        return wrapper
    return decorator
