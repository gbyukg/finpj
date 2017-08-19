import json
import os

params = json.loads(os.environ['_._'])

############### SC source from ##############
# [0]: GIT
# [1]: PACKAGE
#############################################
f = lambda i: params['source_from'][i][params['source_from'][i]['name']].strip()
source_from_dic = {params['source_from'][i]['name']:f(i) for i in (0,1) if f(i)}

if len(source_from_dic) == 0:
    raise SystemExit("no source specified")

for key, val in source_from_dic.iteritems():
    source_from = "--{} {}".format(key, val.strip().replace('\n', ' '))

############### install method ##############
# [0]: RESTORE
# [1]: FULL_INSTALL
# Extend parametes:
#     RUN_UNIT: --UT
#     RUN_AVL: --avl
#     RUN_DATALOADER: --data-loader
#############################################
install_method = ''
extend_par = ''
base_db = params['install_method'][0]['base_db'].strip()
if base_db:
    extend_par = params['install_method'][0]
    install_method = '--restore-install {}'.format(base_db)
else:
    extend_par = params['install_method'][1]
    install_method = '--full-install'

install_parameters = "{} {} {} {} {} {} --keep-alive {} {} {} {} --instance-name {} --instance-db-name {} {}".format(
    source_from,
    install_method,
    '--data-loader' if extend_par['run_dataloader'] else '',
    '--avl' if extend_par['run_avl'] else '',
    '--ut' if extend_par['run_unit'] else '',
    '--as-base-db' if extend_par.get('as_base_db', None) else '',
    params['keep_live'] if params['keep_live'] else '3',
    '--bp-instance' if params['install_bp'] else '',
    '--independent-es' if params['independent_es'] else '',
    '--qrr' if params['run_qrr'] else '',
    params['instance_name'] if params['instance_name'] else os.environ['BUILD_ID'],
    params['db_name'] if params['db_name'] else 'DB_{}'.format(os.environ['BUILD_ID']),
    '--cus-install-hook {}'.format(params['atoi_install_hook']) if params['atoi_install_hook'] else '',
)

print(install_parameters)
