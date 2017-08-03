# encoding: utf-8
'''
Created on 2017年7月24日

@author: zzlzhang@cn.ibm.com
'''


from socket import gethostname
#from os.path import split as os_path_split
from os import getenv as os_getenv
import sys
import ConfigParser


'''
Load configurations from config file
'''


class GetConfigs(object):
    '''Load configurations from config file'''
    project_dir = sys.modules['__main__'].sys.path[0]
    # 其实不需要使用 try 来判断 configParrser 是否已经存在
    try:
        GetConfigs.configParrser
    except NameError:
        configParrser = ConfigParser.SafeConfigParser(
            {
                'host_name': gethostname(),
                'project_dir': project_dir
            }
        )
        loaded_config_file = configParrser.read(
            '{}/configs/install_config.cfg'.format(
                project_dir
            )
        )

    @classmethod
    def get_all_configs(cls, section):
        '''Get All configurations'''
        try:
            confs = cls.configParrser.items(section)
        except ConfigParser.NoSectionError:
            if len(cls.loaded_config_file) == 0:
                raise ConfigParser.NoSectionError('No configuration file find.')
            else:
                msg = 'Load config file failed: No section [{}]\nConfig file: {}'.format(
                        section,
                        cls.loaded_config_file)
                raise ConfigParser.NoSectionError(msg)
        except ConfigParser.InterpolationSyntaxError as e:
            raise ConfigParser.InterpolationSyntaxError("Config file syntax error: {}".format(e))
        except Exception as e:
            raise Exception(e)

        # https://stackoverflow.com/questions/5466618/too-many-values-to-unpack-iterating-over-a-dict-key-string-value-list
        # 环境变量(大写)优先于配置文件
        return {key: os_getenv(key.upper(), val) for key, val in confs}

    @classmethod
    def get_config(cls, setction, key):
        '''get a particular configuration'''
        pass


if __name__ == '__main__':
    GetConfigs.get_all_configs('dev01')
