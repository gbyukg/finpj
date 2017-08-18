#!/usr/bin/env python
# encoding: utf-8
'''
Created on 2017年7月24日

@author: zzlzhang@cn.ibm.com
'''

import os
import sys
import requests
import datetime
from argparse import ArgumentParser, Action
from finpj import *


install_flgs = InstallFlag(
    0x00,  # source_from_package
    0x01,  # source_from_git
    0x00,  # restore_install
    0x02,  # full_install
    0x04,  # init_db
    0x08,  # as_base_db
    0x10,  # data_loader
    0x20,  # avl
    0x40,  # ut
    0x80,  # independent_es
    0x100, # qrr
    0x200, # debug
    0x400, # bp_instance
)


class Install(object):
    def __init__(self, *args, **kvargs):
        # https://stackoverflow.com/questions/38987/how-to-merge-two-python-dictionaries-in-a-single-expression
        # 合并配置文件中读取的配置和命令行指定的选项
        self.install_config = dict(GetConfigs.get_all_configs(kvargs['conf_section']).items() + kvargs.items())

        # 设置 tmp 目录
        self.__setup_tmpdir()

        # install_method:
        #   0: --restore-install
        #   1: --full-install 数据库恢复而来, 安装时不需要初始化数据库, dataloader
        #
        # 恢复数据库安装
        # install_method = 0x02 # (--restore-install, --full-install)
        if self.install_config['flags'] & install_flgs.full_install == install_flgs.restore_install:
            # 关闭 init_db
            self.install_config['flags'] &= ~install_flgs.init_db
            # 关闭 dataloader
            # self.install_config['flags'] &= ~install_flgs.data_loader
            # db_restore hook 使用
            self.install_config['db_restore_logpath'] = '{}/log_path'.format(self.install_config['tmp_dir'])
            self.install_config['db_restore_logtarget'] = '{}/log_target'.format(self.install_config['tmp_dir'])
            self.install_config['db_restore_artifacts_dir'] = '{}/artifacts'.format(self.install_config['tmp_dir'])
            self.install_config['db_source_file_name'] = self.install_config['db_source_file_name'][0]

        # 如果实例将被用作基础数据库, 将总是执行 init_db 和 dataloader
        #if self.install_config['flags'] & install_flgs.as_base_db == install_flgs.as_base_db:
            # 开启 dataloader
            #self.install_config['flags'] |= install_flgs.data_loader

        # 设置 dataloader 目录, git 与 package dataloader 路径不同
        # package: False 0
        # git: True 1
        # [self.install_config['source_from']]
        self.install_config['dataloader_dir'] = (
            '{:s}/ibm/dataloaders'.format(self.install_config['tmp_dir']),  # package dataloader
            "{:s}/ibm/dataloaders".format(self.install_config['git_dir'])  # git dataloader
            )[self.install_config['flags'] & install_flgs.source_from_git]

        # 将配置文件写入到文件中, 当做环境变量传递给shell脚本
        env_file = "{:s}/env.sh".format(self.install_config['tmp_dir'])
        fh = open(env_file, "w+", buffering=1)
        for key, val in self.install_config.iteritems():
            fh.write("{}=\"{}\"\n".format(key.upper(), val))
        fh.close()

        # 设置 BASH_ENV 环境变量, 执行脚本时自动读取该文件获取环境变量
        os.environ["BASH_ENV"] = env_file

        run_script('info')
        self.install_sc()

    def __setup_tmpdir(self):
        keep_live = int(self.install_config['keep_alive'])
        # 因为一直是当天的凌晨做清理操作, 所有默认在追加一天
        time_dir = (datetime.datetime.today() + datetime.timedelta(days=keep_live+1)).strftime("%Y-%m-%d")

        print_msg("The instance will be deleted on {0:s}".format(time_dir))
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
            (self._install_from_package, self._install_from_git)[self.install_config['flags'] & install_flgs.source_from_git]()
            func(self)
        return wrapper

    def _get_pr_info(self, pr_number):
        headers = {
            'user-agent': 'zzlzhang',
            'Content-Type': 'application/json',
            'Authorization': "token {0:s}".format(self.install_config['github_token']),
        }
        url = "https://api.github.com/repos/sugareps/Mango/pulls/{:s}".format(pr_number)
        response = requests.get(url, headers=headers)

        if not response.ok:
            response.raise_for_status()
        return response.text

    def _install_from_git(self):
        print_header_msg("****** Install from GIT... ******")
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

    def _install_from_package(self):
        print_header_msg('install from package')
        remote = 0
        locally = 1
        f = lambda idx, p: '{}^{}'.format(remote, p, idx) if p.startswith('http') else '{}^{}'.format(locally, p, idx)
        params = [f(idx, package.strip()) for idx, package in enumerate(self.install_config['source_code'])]
        cus_params = ' '.join(params)
        run_script('prepare_source_from_package', cus_param=cus_params)

    @_prepare_source_code
    def install_sc(self):
        '''安装SC, 两种方式:
               一步一步安装 :install_step_by_step
               恢复安装     :install_from_restore, 必须选择要恢复的数据库
        '''
        insc = InstallSC(self.install_config['flags'] & install_flgs.full_install)
        try:
            insc(**self.install_config)
        except InstallFailedException as e:
            # stderr
            raise SystemExit(e)
        except Exception as e:
            raise SystemExit(e)


class CusAction(Action):
    _flag_control = 0

    def __init__(self, option_strings, dest='flags', nargs=0, default=False, required=False, help=None, **kwargs):
        super(CusAction, self).__init__(
            option_strings=option_strings,
            dest='flags',
            nargs=nargs,
            default=default,
            required=required,
            help=help
        )
        for key, value in kwargs.iteritems():
            setattr(self, key, value)

    def __call__(self, parser, namespace, values, option_string=None):
        '''
        --restore-install: 需要一个参数
        '''
        # 只有打开标志位, 没有关闭标志位, 所以全部为 或 操作.
        CusAction._flag_control |= self.const

        # self.dest 永远等于 flags
        setattr(namespace, self.dest, CusAction._flag_control)
        try:
            # 捕获到 AttributeError 说明没有 self.cus_dest, 则不设置该值, 直接忽略错误
            setattr(namespace, self.cus_dest, values)
        except AttributeError:
            pass


def parse_args():
    parser = ArgumentParser(
        prog="install.py",
        description="SC DevOps tools",
        epilog="Have a Good Day ^.^"
    )
    installSubparsers = parser.add_subparsers(
        title='title',
        description='description',
        prog='install.py',
    )

    # install a new SC
    install_sc_args = installSubparsers.add_parser(
        'install',
        help='''
        Install a new SC instance.
        Type `install.py install -h` to get install help'''
    )
    # 设置要执行的函数名
    install_sc_args.set_defaults(func='install_sc')

    # --git | --package
    arg_get_code_method_group = install_sc_args.add_mutually_exclusive_group(required=True)
    arg_get_code_method_group.add_argument(
        '--package',
        action=CusAction,
        nargs='+',
        cus_dest='source_code',
        const=install_flgs.source_from_package,  # 0
        help='Install from SC ZIP packages.'
    )
    arg_get_code_method_group.add_argument(
        '--git',
        action=CusAction,
        const=install_flgs.source_from_git,  # 1
        cus_dest='source_code',
        nargs='+',
        help='Install from GIT repository.'
    )

    install_sc_args.add_argument(
        '--conf-section',
        action='store',
        dest='conf_section',
        required=True,
        help='Config section in [install_config.cfg]'
    )

    # --full-install | --restore-install
    arg_install_method_group = install_sc_args.add_mutually_exclusive_group(required=True)
    arg_install_method_group.add_argument(
        '--restore-install',
        action=CusAction,
        cus_dest='db_source_file_name',  # 用来存储备份数据库名字
        nargs=1,  # 此处需要一个参数, 用来指定备份数据库的名字
        const=install_flgs.restore_install,  # 0
        help='''During the installation, it will not initialize database and create tables etc.,
        but restore DB from a DB backup file.'''
    )
    arg_install_method_group.add_argument(
        '--full-install',
        action=CusAction,
        const=install_flgs.full_install,  # 1
        help='Install SC step by step, this means it will initialize a new database and create all tables during the installation.'
    )

    install_sc_args.add_argument(
        '--instance-name',
        action='store',
        dest='instance_name',
        default='sugarcrm',
    )
    install_sc_args.add_argument(
        '--instance-db-name',
        action='store',
        dest='db_name',
        default='saleconn',
    )
    install_sc_args.add_argument(
        '--keep-alive',
        action='store',
        dest='keep_alive',
        type=int,
        choices=range(1, 30),
        default=3,
    )

    install_sc_args.add_argument(
        '--init-db',
        action=CusAction,
        const=install_flgs.init_db,
        help='Run DB initialize script, it will create a new database with the name specified by --db_name parameter'
    )
    install_sc_args.add_argument(
        '--as-base-db',
        action=CusAction,
        const=install_flgs.as_base_db,
        help='''If this parameter is provided, backup this database,
        and the database will be used as base database, and the backup file can be used as by other SC instance which install with --restore paramter'''
    )
    install_sc_args.add_argument(
        '--data-loader',
        action=CusAction,
        const=install_flgs.data_loader,
        help='''Run dataloader after install.
        Default = False'''
    )
    install_sc_args.add_argument(
        '--avl',
        action=CusAction,
        const=install_flgs.avl,
        help="Import AVL data."
    )
    install_sc_args.add_argument(
        '--ut',
        action=CusAction,
        const=install_flgs.ut,
        help='Run PHP Unittest after install.'
    )
    install_sc_args.add_argument(
        '--independent-es',
        action=CusAction,
        const=install_flgs.independent_es,
        help='Create a new Independent ES instance.'
    )
    install_sc_args.add_argument(
        '--qrr',
        action=CusAction,
        const=install_flgs.qrr,
    )
    install_sc_args.add_argument(
        '--cus-install-hook',
        action='store',
        dest='cus_install_hook',
        help='custom install hook script'
    )
    install_sc_args.add_argument(
        '--debug',
        action=CusAction,
        const=install_flgs.debug,
    )
    install_sc_args.add_argument(
        '--bp-instance',
        action=CusAction,
        const=install_flgs.bp_instance,
    )

    args = vars(parser.parse_args())

    try:
        {
            'install_sc': Install,
        }[args['func']](**args)
    except KeyError as e:
        raise SystemExit("Error: Key [{:s}] does not exists.".format(e))
    except AttributeError as e:
        raise SystemError("Error: Attribute [{:s}] does not exists.".format(e))
    except Exception as e:
        raise SystemError(e)


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