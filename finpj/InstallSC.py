# encoding: utf-8
'''
Created on 2017年7月24日

@author: zzlzhang@cn.ibm.com
'''

import requests
from installHooks import installHooks, run_script

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
            return (self.install_from_restore, self.install_step_by_step)[self.approach](*args, **kvargs)
        except KeyError:
            raise InstallFailedException(
                'Error: Currently, only support [install_step_by_step] and [install_from_restore]'
            )

    @installHooks('install_sbs')
    def install_step_by_step(self, *args, **kvargs):
        try:
            kvargs['instance_url'] = '{}/{}'.format(kvargs['web_host'], kvargs['instance_name'])
            kvargs['install_url'] = '{}/install.php'.format(kvargs['instance_url'])
            self.install_steps_data = (
                {'step': 0},
                # 0
                {
                    "current_step": 0,
                    "goto": "Next",
                    "language": "en_us",
                    "instance_url": kvargs['install_url'],
                },
                # 1
                {
                    "current_step": 1,
                    "goto": "Next",
                },
                # 2
                {
                    "checkInstallSystem": "true",
                    "to_pdf": "1",
                    "sugar_body_only": "1"
                },
                # 3
                {
                    "current_step": 2,
                    "goto": "Next",
                    "setup_license_accept": "on",
                },
                # 4
                {
                    "current_step": 3,
                    "goto": "Next",
                    "install_type": "custom",
                    "setup_license_key": kvargs['sc_license'],
                },
                # 5
                {
                    "current_step": 4,
                    "goto": "Next",
                    "setup_db_type": "ibm_db2",
                },
                # 6
                {
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
                },
                # 7
                {
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
                },
                {
                    "current_step": 6,
                    "goto": "Next",
                    "setup_system_name": "SugarCRM",
                    "setup_site_admin_user_name": kvargs['site_admin_user'],
                    "setup_site_admin_password": kvargs['site_admin_pwd'],
                    "site_admin_pwd": kvargs['site_admin_pwd'],
                    "setup_site_url": kvargs['instance_url'],
                },
                {
                    "current_step": 7,
                    "goto": "Next",
                    "setup_site_sugarbeet_anonymous_stats": "yes",
                    "setup_site_session_path": "",
                    "setup_site_log_dir": "",
                    "setup_site_guid": "",
                },
                # install 之后开始安装
                {
                    "current_step": 8,
                    "goto": "Next",
                },
                {
                    "current_step": 9,
                    "goto": "Next",
                },
                {
                    "current_step": 10,
                    "goto": "Next",
                    "language": "en_us",
                    "install_type": "custom",
                    "default_user_name": kvargs['site_admin_user'],
                },
                {
                    "default_user_name": kvargs['site_admin_user'],
                    "next": "Next",
                },
            )
        except KeyError as e:
            raise InstallFailedException("Error: [install_step_by_step] can not find config key: {}".format(e))
        except Exception as e:
            raise InstallFailedException("Error: [install_step_by_step] {}".format(e))
        return 0
        reqSessiong = requests.Session()
        reqSessiong.get(kvargs['install_url'])
        for step in iter(self.install_steps_data):
            print(step)
            response = reqSessiong.post(kvargs['install_url'], data=step)
            if not response.ok:
                response.raise_for_status()

    @installHooks('install_restore')
    def install_from_restore(self, *args, **kvargs):
        run_script('install_from_restore')


if __name__ == '__main__':
    insc = InstallSC(
        'install_step_by_step',
        sc_license='1234567890',
        db_name='DB_89',
        db_host='dev01.rtp.raleigh.ibm.com',
        db_port='50000',
        db_admin_usr='btit',
        db_admin_pwd='btit@ibm',
        fts_type='Elastic',
        fts_host='dev02.rtp.raleigh.ibm.com',
        fts_port='9200',
        site_admin_user='admin',
        site_admin_pwd='asdf',
        instance_name='89',
        web_host='http://dev01.rtp.raleigh.ibm.com',
    )

    try:
        insc()
    except InstallFailedException as e:
        print(e)
    except Exception as e:
        print(e)
