# encoding: utf-8
'''
Created on 2017年7月24日

@author: zzlzhang@cn.ibm.com
'''

from __future__ import print_function
import os
import sys
import requests
import datetime
from argparse import ArgumentParser
from finpj import InstallSC, InstallFailedException, GetConfigs, run_script


class Install(object):
    def __init__(self, *args, **kvargs):
        # https://stackoverflow.com/questions/38987/how-to-merge-two-python-dictionaries-in-a-single-expression
        # 合并配置文件中读取的配置和命令行指定的选项
        self.install_config = dict(GetConfigs.get_all_configs(kvargs['conf_section']).items() + kvargs.items())
        
        self.__setup_tmpdir()
        
        # 将配置文件写入到文件中, 当做环境变量传递给shell脚本
        env_file="{:s}/env.sh".format(self.install_config['tmp_dir'])
        fh = open(env_file, "w+", buffering=1)
        for key,val in self.install_config.iteritems():
            fh.write("{}=\"{}\"\n".format(key.upper(), val))
        fh.close()
        
        # 设置 BASH_ENV 环境变量, 执行脚本时自动读取该文件获取环境变量
        os.environ["BASH_ENV"] = env_file

        self.install_sc()
    
    def __setup_tmpdir(self):
        keep_live = int(self.install_config['keep_alive'])
        # 因为一直是当天的凌晨做清理操作, 所有默认在追加一天
        time_dir = (datetime.datetime.today() + datetime.timedelta(days=keep_live+1)).strftime("%Y-%m-%d")
        
        print("The instance will be deleted on {0:s}".format(time_dir))
        tmp_dir = "{0:s}/{1:s}/{2:s}".format(self.install_config['tmp_path'],
                                              time_dir,
                                              self.install_config["instance_name"])
        if not os.path.exists(tmp_dir):
            os.makedirs(tmp_dir)
        
        # 追加到 config 配置中
        self.install_config["tmp_dir"] = tmp_dir
        self.install_config["log_file"] = "{}/install.log".format(tmp_dir)
    
    def _prepare_source_code(func):
        # 此处代码在文件被加载时就已经被执行, 因此此处并无 self 变量
        def wrapper(self):
            # git => True
            # package => False
            (self._install_from_package, self._install_from_git)[self.install_config['source_from']]()

            if self.install_config['restore_install']:
                #self.install_config['install_method'] = 'install_from_restore'
                self.install_config['init_db'] = False
                self.install_config['data_loader'] = False
            else:
                pass
                #self.install_config['install_method'] = 'install_step_by_step'
            
            func(self)
        return wrapper
    
    def _get_pr_info(self, pr_number):
        headers = {
            'user-agent': 'zzlzhang',
            'Content-Type': 'application/json',
            'Authorization': "token {0:s}".format(self.install_config['github_token']),
        }
        url="https://api.github.com/repos/sugareps/Mango/pulls/{:s}".format(pr_number)
        response = requests.get(url, headers=headers)
        
        if not response.ok:
            response.raise_for_status()
        return response.text
    
    def _install_from_git(self):
        refs = ''
        for sour in self.install_config['source_code']:
            try:
                float(sour)
            except ValueError:
                # branch
                try:
                    br_ref, br_name = sour.split(':')
                except ValueError:
                    br_ref = 'sugareps'
                    br_name = sour
                refs = '{}br:{:s}:{:s} '.format(refs, br_ref, br_name)
            else:
                # PR
                '''
                pr_info = jsloads(self._get_pr_info(sour))
                if pr_info['merged']:
                    raise "PR [{:s}] already has been merged, can not install from it.".format(sour)
                '''
                refs = '{}pr:sugareps:{:s} '.format(refs, sour)

        refs = refs.strip()
        if not refs:
            raise "No any GIT source can be used."
        
        run_script('prepare_source_from_pr', cus_param=refs)
        
        # build sugar code
        run_script('build_code')
    
    def _install_from_br(self):
        pass
    
    def _install_from_package(self):
        pass

    @_prepare_source_code
    def install_sc(self):
        '''安装SC, 两种方式: 
               一步一步安装 :install_step_by_step
               恢复安装     :install_from_restore, 必须选择要恢复的数据库
        '''

        insc = InstallSC(self.install_config['install_method'])
        try:
            insc(**self.install_config)
        except InstallFailedException as e:
            # stderr
            raise SystemExit(e)
        except Exception as e:
            raise SystemExit(e)


'''
解析参数
'''
def parse_args():
    parser = ArgumentParser(
        prog="install.py",
        description="SC DevOps tools",
        epilog="Have a Good Day ^.^"
    )
    subparsers = parser.add_subparsers(prog='Install a new SC instance')

    # install a new SC
    arg_install_sc = subparsers.add_parser('install', help='patch help')
    
    arg_install_sc.add_argument(
        '--type',
        dest="type",
        type=str,
        default="install_sc",
        help='Install a new SC instance'
    )
    
    # --git | --package
    arg_get_code_method_group = arg_install_sc.add_mutually_exclusive_group(required=True)
    arg_get_code_method_group.add_argument(
        '--git',
        action='store_true',
        dest='source_from',
        help='Install from GIT source'
    )
    arg_get_code_method_group.add_argument(
        '--package',
        action='store_false',
        dest='source_from',
        help='Install from Build Package'
    )
    
    arg_install_sc.add_argument(
        '--source-code',
        action='store',
        dest='source_code',
        nargs='+',
        required=True,
    )
    
    arg_install_sc.add_argument(
        '--conf-section',
        action='store',
        dest='conf_section',
        required=True,
    )
    
    # --full-install | --restore-install
    arg_install_method_group = arg_install_sc.add_mutually_exclusive_group(required=True)
    arg_install_method_group.add_argument(
        '--full-install',
        action='store_true',
        dest='install_method',
        help='Install SC step by step')
    arg_install_method_group.add_argument(
        '--restore-install',
        action='store_false',
        dest='restore_install',
        help='Restore SC and DataBase')
    arg_install_sc.add_argument(
        '--db-source',
        action='store',
        dest='db_source',
        default='saleconn',
    )
    
    arg_install_sc.add_argument(
        '--instance-name',
        action='store',
        dest='instance_name',
        default='sugarcrm',
    )
    arg_install_sc.add_argument(
        '--instance-db-name',
        action='store',
        dest='db_name',
        default='saleconn',
    )
    arg_install_sc.add_argument(
        '--keep-alive',
        action='store',
        dest='keep_alive',
        type=int,
        choices=range(1, 30),
        default=3,
    )
    
    # 是否初始化数据库
    arg_init_db_group = arg_install_sc.add_mutually_exclusive_group(required=True)
    arg_init_db_group.add_argument(
        '--init-db',
        action='store_true',
        dest='init_db',
    )
    arg_init_db_group.add_argument(
        '--no-init-db',
        action='store_false',
        dest='init_db',
    )
    
    # dataloader
    arg_run_dataloader_group = arg_install_sc.add_mutually_exclusive_group(required=True)
    arg_run_dataloader_group.add_argument(
        '--data-loader',
        action='store_true',
        dest='data_loader',
    )
    arg_run_dataloader_group.add_argument(
        '--no-data-loader',
        action='store_false',
        dest='data_loader',
    )
    
    # avl
    arg_run_avl_group = arg_install_sc.add_mutually_exclusive_group(required=True)
    arg_run_avl_group.add_argument(
        '--avl',
        action='store_true',
        dest='avl',
    )
    arg_run_avl_group.add_argument(
        '--no-avl',
        action='store_false',
        dest='avl',
    )
    
    # unittest
    arg_run_unittest_group = arg_install_sc.add_mutually_exclusive_group(required=True)
    arg_run_unittest_group.add_argument(
        '--ut',
        action='store_true',
        dest='ut',
    )
    arg_run_unittest_group.add_argument(
        '--no-ut',
        action='store_false',
        dest='ut',
    )
    
    arg_install_sc.add_argument(
        '--independent-es',
        action='store_true',
        dest='independent_es',
    )
    arg_install_sc.add_argument(
        '--cus-install-hook',
        action='store',
        dest='cus_install_hook',
    )
    arg_install_sc.add_argument(
        '--debug',
        action='store_true',
        dest='debug',
    )

    args = vars(parser.parse_args())
    try:
        {
            'install_sc': Install,
        }[args['type']](**args)
    except KeyError as e:
        print(e, file=sys.stderr)
    except AttributeError as e:
        print(e, file=sys.stderr)
    except Exception as e:
        print(e, file=sys.stderr)
        #file=sys.stderr


# Namespace(func='install_sc', restore_install=False, source_code=['11223', 'sugareps:ibm_r40', 'prod.zip'])
# install.py install \
# --conf-section dev01
# --full-install/--restore-install \
# --db-source saleconn \
# --instance-name 68 \
# --instance-db-name DB_68 \
# --init-db \
# --keep-alive 5 \
# --git \
# --source-code 32599 32601 \
# --[no-]data-loader \
# --[no-]avl \
# --[no-]ut \
# --independent-es
parse_args()
