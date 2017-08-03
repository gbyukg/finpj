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
    '''
    #for token in lexer:
    #    print repr(token)
    # 传递给 hook 脚本的自定义参数, key 值必须为 cus_param
    try:
        cus_param = kvargs.pop('cus_param')
    except KeyError:
        cus_param = None
    # 所有配置都将以 key=value 方式传递给 hook 脚本
    # hook 脚本将直接使用这些键值对来设置成环境变量
    # 参数格式为: install_hook.sh hook_name 3(获取到的配置属相) "n1=m1" "n2=m2" "n3=m3" 自定义参数

    for key, val in kvargs.iteritems():
        if type(val) is str or type(val) is type(0):
            print(key.upper())
            print(val)
        else:
            if not val:
                print(0)
            else:
                ' '.join(val)

    hook_args = ' '.join(['"{}={}"'.format(key.upper(), val if type(val) is str or type(val) is type(0) else (0 if not val else ' '.join(val))) for key, val in kvargs.iteritems()])
    # 自定义参数一定要放到最后
    hook_args = hook_args if cus_param is None else '{} {}'.format(hook_args, cus_param)

    cmd = "{}/install_hook.sh {} {:d} {}".format(
        os.path.split(os_modules['__main__'].__file__)[0],
        func_name,
        len(kvargs), # 定义环境变量个数`1234567890-
        hook_args
    )
    '''
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
        if status >> 0x8 != 0:
            err_msg = "[install_hook {0:s}] error. Exit code: [{1:s}]".format(func_name, str(status >> 0x8))
            raise OSError(err_msg)
    except KeyboardInterrupt as e:
        print e
        exit(1)


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
