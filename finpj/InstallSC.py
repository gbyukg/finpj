# encoding: utf-8
'''
Created on 2017年7月24日

@author: zzlzhang@cn.ibm.com
'''

import requests
from .InstallHooks import *
from .Common import *

__all__ = [
    'InstallFailedException',
    'InstallSC'
]

class InstallFailedException(Exception): pass


class InstallSC(object):
    '''
    Install SC instance
    '''

    def __init__(self, approach=False, **kvargs):
        '''
        Constructor
        '''
        self.approach = approach

    def __call__(self, *args, **kvargs):
        try:
            # --full-install: True 1
            # --restore-install : False 0
            return (self.install_from_restore, None, self.install_step_by_step)[self.approach](*args, **kvargs)
        except KeyError:
            raise InstallFailedException(
                'Error: Currently, only support [install_step_by_step] and [install_from_restore]'
            )

    def _install_params(self, *args, **kvargs):
        yield {'step': 0}

        print_header_msg("Current step [0]")
        yield {
            "current_step": 0,
            "goto": "Next",
            "language": "en_us",
            "instance_url": kvargs['install_url'],
        }

        print_header_msg("Current step [1]...")
        yield {
            "current_step": 1,
            "goto": "Next",
        }
        yield {
            "checkInstallSystem": "true",
            "to_pdf": "1",
            "sugar_body_only": "1"
        }

        print_header_msg("Current step [2]...")
        yield {
            "current_step": 2,
            "goto": "Next",
            "setup_license_accept": "on",
        }

        print_header_msg("Current step [3]...")
        yield {
            "current_step": 3,
            "goto": "Next",
            "install_type": "custom",
            "setup_license_key": kvargs['sc_license'],
        }

        print_header_msg("Current step [4]...")
        yield {
            "current_step": 4,
            "goto": "Next",
            "setup_db_type": "ibm_db2",
        }

        print_header_msg("Checking DB ...")
        yield {
            "checkDBSettings": "true",
            "to_pdf": 1,
            "sugar_body_only": 1,
            "demoData": "no",
            "setup_db_database_name": kvargs['db_name'],
            "setup_db_host_name": kvargs['db_host'],
            "setup_db_port_num": kvargs['db_port'],
            "setup_db_admin_user_name": kvargs['db_admin_usr'],
            "setup_db_admin_password": kvargs['db_admin_pwd'],
            "setup_fts_type": kvargs['fts_type'],
            "setup_fts_host": kvargs['fts_host'],
            "setup_fts_port": kvargs['fts_port'],
        }

        print_header_msg("Current step [5]...")
        yield {
            "current_step": 5,
            "goto": "Next",
            "setup_db_drop_tables": "",
            "setup_db_create_sugarsales_user": "",
            "demoData": "no",
            "setup_db_database_name": kvargs['db_name'],
            "setup_db_host_name": kvargs['db_host'],
            "setup_db_port_num": kvargs['db_port'],
            "setup_db_admin_user_name": kvargs['db_admin_usr'],
            "setup_db_admin_password": kvargs['db_admin_pwd'],
            "setup_db_admin_password_entry": kvargs['db_admin_pwd'],
            "setup_fts_type": kvargs['fts_type'],
            "setup_fts_host": kvargs['fts_host'],
            "setup_fts_port": kvargs['fts_port'],
        }

        print_header_msg("Current step [6]...")
        yield {
            "current_step": 6,
            "goto": "Next",
            "setup_system_name": "SugarCRM",
            "setup_site_admin_user_name": kvargs['site_admin_user'],
            "setup_site_admin_password": kvargs['site_admin_pwd'],
            "site_admin_pwd": kvargs['site_admin_pwd'],
            "setup_site_url": kvargs['instance_url'],
        }

        print_header_msg("Current step [7]...")
        yield {
            "current_step": 7,
            "goto": "Next",
            "setup_site_sugarbeet_anonymous_stats": "yes",
            "setup_site_session_path": "",
            "setup_site_log_dir": "",
            "setup_site_guid": "",
        }
        # install 之后开始安装
        print_header_msg("Current step [8]: Installing...")
        yield {
            "current_step": 8,
            "goto": "Next",
        }

        print_header_msg("Current step [9]...")
        yield {
            "current_step": 9,
            "goto": "Next",
        }

        print_header_msg("Current step [10]...")
        yield {
            "current_step": 10,
            "goto": "Next",
            "language": "en_us",
            "install_type": "custom",
            "default_user_name": kvargs['site_admin_user'],
        }

        print_header_msg("Preparing web page...")
        yield {
            "default_user_name": kvargs['site_admin_user'],
            "next": "Next",
        }

    @installHooks('install')
    def install_step_by_step(self, *args, **kvargs):
        print_header_msg("Starting to install Step by Step")

        kvargs['instance_url'] = '{}/{}'.format(kvargs['web_host'], kvargs['instance_name'])
        kvargs['install_url'] = '{}/install.php'.format(kvargs['instance_url'])

        reqSessiong = requests.Session()
        try:
            for post_data in self._install_params(*args, **kvargs):
                response = reqSessiong.post(
                    kvargs['install_url'],
                    data=post_data,
                    hooks=dict(response=lambda r, *args, **kvargs: None),
                )
                if response.status_code != requests.codes.ok:
                    response.raise_for_status()
        except KeyError as e:
            raise InstallFailedException("Error: [install_step_by_step] can not find config key: {}".format(e))
        except Exception as e:
            raise InstallFailedException("Error: [install_step_by_step] {}".format(e))

    @installHooks('install')
    def install_from_restore(self, *args, **kvargs):
        print_msg("Install from restore")
        # run_script('install_from_restore')


if __name__ == '__main__':
    def print_header_msg(*args, **kvargs):
        print('messgae')

    def print_msg(*args, **kvargs):
        print('message')
    # http://dev05.rtp.raleigh.ibm.com/170/install.php
    insc = InstallSC(2)

    try:
        insc(
            sc_license='1234567890',
            db_name='DB_3040',
            db_host='dev01.rtp.raleigh.ibm.com',
            db_port='50000',
            db_admin_usr='btit',
            db_admin_pwd='btit@ibm',
            fts_type='Elastic',
            fts_host='dev01.rtp.raleigh.ibm.com',
            fts_port='9200',
            site_admin_user='admin',
            site_admin_pwd='asdf',
            instance_name='304',
            web_host='http://dev01.rtp.raleigh.ibm.com',
        )
    except InstallFailedException as e:
        print(e)
    except Exception as e:
        print(e)
