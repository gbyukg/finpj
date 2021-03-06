#!/usr/bin/env bash

set -o nounset

SCRIPT_NAME=$(basename "$0")

SOURCE_FROM_PACKAGE=0x00
SOURCE_FROM_GIT=0x01
RESTORE_INSTALL=0x00
FULL_INSTALL=0x02
INIT_DB=0x04
AS_BASE_DB=0x08
DATA_LOADER=0x10
AVL=0x20
UT=0x40
INDEPENDENT_ES=0x80
QRR=0x100
DEBUG=0x200
BP_INSTANCE=0x400

_print_msg()
{
    printf "\n\e[35m%s [ %s ] %s\e[0m\n" ">>>>>> " "$1" " <<<<<<"
}

_red_echo()
{
    printf "\n\e[31m%s\e[0m\n" "$@"
}

_green_echo()
{
    printf "\n\e[32m%s\e[0m\n" "$@"
}

__logging()
{
    local FUN_NAME="${1}"
    local LINE_NO="${2}"
    local LEVEL="${3}"
    local MSG="${4}"

    echo "[$(date '+%F %T')] [$0:${FUN_NAME}:${LINE_NO}] [${LEVEL}] ${MSG}" >> "${LOG_FILE}"
}

__err()
{
    local parent_lineno="${1-$LINENO}"
    local message="${2-'Unknown Error'}"
    local code="${3-1}"
    echo "[${SCRIPT_NAME}] [$(date '+%D %H:%M:%S')] ERROR[${parent_lineno}]: ${message}" >&2
    exit "${code}"
}

__command_logging_and_exit()
{
    local FUN_NAME="${1}"
    local LINE_NO="${2}"
    local cmd="${3}"
    local print_msg="${4:-0}"
    local msg=""

    msg=$(2>&1 eval "${cmd}")
    return_code="$?"

    if [[ 0 -eq "${return_code}" ]]; then
        [[ ${print_msg} -eq 1 || $(($FLAGS & $DEBUG)) -eq $DEBUG ]] && echo "${msg}"
        __logging "$FUN_NAME" "$LINE_NO" "SH-COMMAND:${return_code}" "${cmd}"
    else
        echo "SH-COMMAND[${return_code}] ${cmd}; Message: [${msg}]"
        __logging "$FUN_NAME" "$LINE_NO" "SH-COMMAND:${return_code}" "${cmd}; Message: [${msg}]"
        exit 1
    fi
}

__stop_db_app()
{
    local circularCount="${1:-1}"
    _green_echo "Cleaning DB connections, time [${circularCount}]"

    for app in $(db2 list applications for database ${DB_NAME} | awk '/[0-9]/{print $3}')
    do
        __logging "${FUNCNAME[0]}" "$LINENO" "INFO" "Stoping DB2 application [${app}]"
        db2 "force application ( $app )"
    done


    # 检查是否还有连接连到该数据库上
    db2 list applications for database "${DB_NAME}" show detail
    if [[ $? -eq 0 ]]; then
        db2 connect to "${DB_NAME}" && \
        db2 QUIESCE DATABASE IMMEDIATE FORCE CONNECTIONS
        db2 CONNECT RESET
        sleep 5
        # circularCount=$((circularCount + 1))
        # [[ "$circularCount" -eq 6 ]] && return
        __stop_db_app circularCount
    fi

    _green_echo "Cleaned DB connections"
}

info()
{
    echo -e "\n\n\n"

    [[ -d /usr/share/cowsay ]] && \
        curl http://proverbs-app.antjan.us/random | cowsay -f $(basename $(ls /usr/share/cowsay/*.cow | sort -R | head -1))

    echo -e "\n\n"
    _green_echo "SC4IBM: ${WEB_HOST}/${INSTANCE_NAME}"
    [[ $(($FLAGS & $BP_INSTANCE)) -eq $BP_INSTANCE ]] \
        && _green_echo "SC4BP ${WEB_HOST}/${INSTANCE_NAME}_bp"
    _green_echo "WEB IDE: ${WEB_HOST}/${INSTANCE_NAME}/sc_webide"
    echo -e "\n"
    _green_echo "SSH info:"
    _green_echo "ssh btit@${DB_HOST} | PWD: btit@ibm"
    echo -e "\n"
    _green_echo "DB info:"
    _green_echo "Host: ${DB_HOST} | Port: ${DB_PORT}"
    _green_echo "DB Name: ${DB_NAME} | DB User: ${DB_ADMIN_USR} | DB PWD: ${DB_ADMIN_PWD}"
    echo -e "\n\n\n"
}

build_code()
{
    __logging "${FUNCNAME[0]}" "$LINENO" "INFO" "Run hook [build_code]"

    _print_msg "building code..."
    __command_logging_and_exit \
        "${FUNCNAME[0]}" "$LINENO" \
        "cd ${GIT_DIR}/build/rome && php build.php -clean -cleanCache -flav=ult -ver='7.6' -dir=sugarcrm -build_dir=${BUILD_DIR}" 1

    [[ -d "${WEB_DIR}/${INSTANCE_NAME}" ]] && __command_logging_and_exit "${FUNCNAME[0]}" "$LINENO" "rm -rf ${WEB_DIR}/${INSTANCE_NAME}"
    __command_logging_and_exit "${FUNCNAME[0]}" "$LINENO" "mv ${BUILD_DIR}/ult/sugarcrm ${WEB_DIR}/${INSTANCE_NAME}"
}

after_prepare_code()
{
    # update composer
    _print_msg "update composer..."
    cd "${GIT_DIR}"/sugarcrm || exit 1
    COMPOSER_DISABLE_XDEBUG_WARN=1 composer update
}

prepare_source_from_pr()
{
    _print_msg "Preparing git..."

    local PR_NUMS=($@)
    local git_refs=""
    local check_ref=''
    local merge_ref=''
    local middle_ref=''

    cd "${GIT_DIR}" || __err "$LINENO" "Git directory [${GIT_DIR}] not exists."

    __command_logging_and_exit "${FUNCNAME[0]}" "$LINENO" "cd ${GIT_DIR}"
    __command_logging_and_exit "${FUNCNAME[0]}" "$LINENO" "git rev-parse --git-dir"

    for par in "${PR_NUMS[@]}"; do
        IFS=:
        info=($par)
        unset IFS

        git_base_refs="git@github.com:${info[1]}/Mango.git"

        if [[ "X${info[0]}" == 'Xpr' ]]; then
            git_refs="${git_base_refs} +refs/pull/*/head:refs/remotes/${info[1]}/pr/*"
            # 以 / 结尾, git checkout -f sugareps//ibm_r40 将报错, 无法找到匹配
            middle_ref='pr/'
        else
            git_refs="${git_base_refs} +refs/heads/*:refs/remotes/${info[1]}/*"
            middle_ref=''
        fi

        _green_echo "Fetching code ${info[1]}/${info[2]} ... "
        __logging "${FUNCNAME[0]}" "$LINENO" "[info]" "fetch ref: ${git_refs}"
        __command_logging_and_exit "${FUNCNAME[0]}" "$LINENO" "git fetch ${git_refs}" 1 #|| __err "$LINENO" "git fetch failed."

        if [[ -z "${check_ref}" ]]; then
            check_ref="${info[1]}/${middle_ref}${info[2]}"
        else
            merge_ref="${merge_ref} ${info[1]}/${middle_ref}${info[2]}"
        fi
    done

    __command_logging_and_exit "${FUNCNAME[0]}" "$LINENO" "git reset --hard"
    __command_logging_and_exit "${FUNCNAME[0]}" "$LINENO" "git clean -fd"

    __logging "${FUNCNAME[0]}" "$LINENO" "[info]" "fetch check ref: ${check_ref}"
    __command_logging_and_exit "${FUNCNAME[0]}" "$LINENO" "git checkout -f ${check_ref}"
    [[ -n "${merge_ref}" ]] && __command_logging_and_exit "${FUNCNAME[0]}" "$LINENO" "git merge --squash ${merge_ref}"

    __logging "${FUNCNAME[0]}" "$LINENO" "[info]" "update submodule"
    __command_logging_and_exit "${FUNCNAME[0]}" "$LINENO" "git submodule sync"
    __command_logging_and_exit "${FUNCNAME[0]}" "$LINENO" "git submodule update --init --recursive"

    after_prepare_code
}

prepare_source_from_package()
{
    _print_msg 'Prepare source from package ...'

    local fun=(remote locally)
    local pack_list_file="${TMP_DIR}"/package.list

    remote()
    {
        local pak="$1"
        local pak_name=$(basename $pak)

        _green_echo "Downloading package [${pak_name}] ..."
        __command_logging_and_exit "${FUNCNAME[0]}" "$LINENO" "wget -q ${pak} -O ${TMP_DIR}/${pak_name}"
        __logging "${FUNCNAME[0]}" "$LINENO" "[info]" "Downloaded remote package [${pak_name}] from [${pak}]"
        echo "${pak_name}" >> "${pack_list_file}"
    }

    locally()
    {
        local pak="$1"
        local pak_name=$(basename $pak)

        _green_echo "Copying package [${pak_name}] ..."
        [[ ! -f "$pak" ]] && __err "$LINENO" "SC package [${pak}] does not exist."
        __command_logging_and_exit "${FUNCNAME[0]}" "$LINENO" "cp $pak ${TMP_DIR}/${pak_name}"
        __logging "${FUNCNAME[0]}" "$LINENO" "[info]" "Copied locally package [${pak_name}] from [${pak}]"
        echo "${pak_name}" >> "${pack_list_file}"
    }

    # 安装时将根据 package.list 列表里的顺序进行打包
    # 第一个包将作为基础包
    cat /dev/null > "${pack_list_file}"
    for package in "$@"; do
        IFS=^
        info=($package)
        unset IFS
        ${fun[info[0]]} "${info[1]}"
    done

    # 解压文件里的第一个压缩包, 基础包
    base_package=$(head -1  "${pack_list_file}")
    [[ -d "${WEB_DIR}/SugarUlt-Full-7.6.0" ]] \
        && rm -rf "${WEB_DIR}/SugarUlt-Full-7.6.0" \
        && __logging "${FUNCNAME[0]}" "$LINENO" "[info]" "Clean web dir [SugarUlt-Full-7.6.0]"
    [[ -d "${WEB_DIR}/${INSTANCE_NAME}" ]] \
        && rm -rf "${WEB_DIR}/${INSTANCE_NAME}" \
        && __logging "${FUNCNAME[0]}" "$LINENO" "[info]" "Clean web dir [${INSTANCE_NAME}]"

    __command_logging_and_exit "${FUNCNAME[0]}" "$LINENO" "unzip -o ${TMP_DIR}/${base_package} \"SugarUlt-Full-7.6.0/*\" -d ${WEB_DIR}/ > /dev/null"
    __command_logging_and_exit "${FUNCNAME[0]}" "$LINENO" "mv ${WEB_DIR}/SugarUlt-Full-7.6.0 ${WEB_DIR}/${INSTANCE_NAME}"

    # 升级补丁包时会通过判断 SC instance 中是否有 install.log 文件来确定是否是正确是实例目录
    # 如果是通过恢复安装, 并不会产生 install.log 文件, 因此需要手动创建一个
    touch "${WEB_DIR}/${INSTANCE_NAME}"/install.log

    # 包安装时不需要跑 federation 脚本
    # 在最后一个包安装完成后, 跑最后一个包中的脚本
    # mv "${WEB_DIR}/${INSTANCE_NAME}"/custom/install/federated_db_environment/sql "${TMP_DIR}"/sql-back

    # 解压基础包中的 SugarInstanceManger
    __command_logging_and_exit "${FUNCNAME[0]}" "$LINENO" "unzip -o ${TMP_DIR}/${base_package} \"ibm/SugarInstanceManager/*\" -d ${TMP_DIR}/ > /dev/null"
    __command_logging_and_exit "${FUNCNAME[0]}" "$LINENO" "cp -r ${TMP_DIR}/ibm/SugarInstanceManager ${WEB_DIR}/${INSTANCE_NAME}/vendor/sugareps/"
}

upgrade_package()
{
    _print_msg "Starting to upgrade SC package ..."

    local pack_list_file="${TMP_DIR}"/package.list

    [[ ! -f "${pack_list_file}" ]] \
        && _green_echo "No upgrade package found." \
        && return 0

    # 更新基础包中的 SugarInstanceManager 配置
    cd "${TMP_DIR}/ibm/SugarInstanceManager" || __err "$LINENO" "SugarInstanceManager folder does not exist."
    mkdir -p "custom/include/Config/configs"

    # 禁止备份数据库
    sed -i "s/\s*\$su->backup();//g" upgrade.php
    # 禁止重新启动 apache
    sed -i "s/\$success = SystemUtils::apache('restart');/\$success = true;/" include/SugarUpgrader.php

    cat <<SYSCONFIG > custom/include/Config/configs/system.config.php
<?php
\$config['apache_binary'] = '${APACHE_BINARY}';
\$config['apache_user'] = '${APACHE_USER}';
\$config['apache_group'] = '${APACHE_GROUP}';
\$config['temp_dir'] = "${TMP_DIR}/SIM";
SYSCONFIG
    cat <<db2CONFIG > custom/include/Config/configs/db2cli.config.php
<?php
\$config['db2profile'] = '${DB2PROFILE}';
\$config['db2createscript'] = '${SCRIPT_NAME}/initdb.sh';
\$config['db2runas'] = '${DB2RUNAS}';
db2CONFIG
    cat <<logCONFIG > custom/include/Config/configs/logger.config.php
<?php
\$config['log_file'] = '${TMP_DIR}/SugarInstanceManager.log';
\$config['log_dir'] = '${TMP_DIR}/upgrade_log';
logCONFIG

    # 开始升级
    {
        # 忽略第一行, 第一行记录的是基础包, 从第二行开始才是升级包
        read
        while read -r ug_pak || [[ -n "$ug_pak"  ]]; do
            _green_echo "Upgrading SC package [$ug_pak] ..."
            __logging "${FUNCNAME[0]}" "$LINENO" "INFO" "Upgrade package: php upgrade.php --instance_path=${WEB_DIR}/${INSTANCE_NAME} --upgrade_zip=${TMP_DIR}/${ug_pak}"
            php upgrade.php --instance_path="${WEB_DIR}/${INSTANCE_NAME}" --upgrade_zip="${TMP_DIR}/${ug_pak}"
        done
    } < "${pack_list_file}"

    local last_package=$(tail -1 ${pack_list_file})
    # 运行最后一个升级包中的 federation 脚本
    _green_echo "Extract federation scripts from package [${last_package}]"
    __command_logging_and_exit "${FUNCNAME[0]}" "$LINENO" "unzip -o ${TMP_DIR}/${last_package} \"SugarUlt-Full-7.6.0/custom/install/federated_db_environment/*\" -d ${TMP_DIR}/ > /dev/null"
    __command_logging_and_exit "${FUNCNAME[0]}" "$LINENO" "cp -rf ${TMP_DIR}/SugarUlt-Full-7.6.0/custom/install/federated_db_environment/ ${WEB_DIR}/${INSTANCE_NAME}/custom/install"
    __command_logging_and_exit "${FUNCNAME[0]}" "$LINENO" "cp -rf  ${WEB_DIR}/${INSTANCE_NAME}/custom/install/federated_db_environment/runScenario.php ${WEB_DIR}/${INSTANCE_NAME}"
    _green_echo "Starting to run federation scripts [Emulation]"
    __logging "${FUNCNAME[0]}" "$LINENO" "INFO" "Run federation script: php ${WEB_DIR}/${INSTANCE_NAME}/runScenario.php Emulation"
    php "${WEB_DIR}/${INSTANCE_NAME}/runScenario.php" Emulation

    # prepare dataloader
    _green_echo "Extract dataloader file from package [${last_package}]"
    __command_logging_and_exit "${FUNCNAME[0]}" "$LINENO" "unzip -o ${TMP_DIR}/${last_package} \"ibm/dataloaders/*\" -d ${TMP_DIR}/ > /dev/null"
}

init_db()
{
    _print_msg "Creating database ${DB_NAME}..."

    # 移除数据库, 如果已经存在
    [[ $(db2 list db directory | grep -i "${DB_NAME}$" > /dev/null 2>&1; echo $?) -eq 0 ]] \
        && __stop_db_app \
        && __logging "${FUNCNAME[0]}" "$LINENO" "INFO" "Removing DB [${DB_NAME}]" \
        && __command_logging_and_exit "${FUNCNAME[0]}" "$LINENO" "db2 drop database ${DB_NAME}"

    db2 "CREATE DATABASE ${DB_NAME} USING CODESET UTF-8 TERRITORY US COLLATE USING UCA500R1_LEN_S2 PAGESIZE 32 K" # create the database from scratch and enable case-insensitive collation
    db2 "CONNECT TO ${DB_NAME}" # make a connection to update the parameters below
    db2 "UPDATE database configuration for ${DB_NAME} using applheapsz 32768 app_ctl_heap_sz 8192"
    db2 "UPDATE database configuration for ${DB_NAME} using stmtheap 60000"
    db2 "UPDATE database configuration for ${DB_NAME} using locklist 50000"
    db2 "UPDATE database configuration for ${DB_NAME} using indexrec RESTART"
    db2 "UPDATE database configuration for ${DB_NAME} using logfilsiz 1000"
    db2 "UPDATE database configuration for ${DB_NAME} using logprimary 12"
    db2 "UPDATE database configuration for ${DB_NAME} using logsecond 30"
    db2 "UPDATE database configuration for ${DB_NAME} using DATABASE_MEMORY AUTOMATIC" #Prevent memory exceeding
    db2 "UPDATE database configuration for ${DB_NAME} using extended_row_sz enable"
    db2 "UPDATE database configuration for ${DB_NAME} using PCKCACHESZ 128000"
    db2 "UPDATE database configuration for ${DB_NAME} using CATALOGCACHE_SZ 400"
    db2set DB2_COMPATIBILITY_VECTOR=4008
    db2 "CREATE BUFFERPOOL SUGARBP IMMEDIATE  SIZE 1000 AUTOMATIC PAGESIZE 32 K"
    db2 "CREATE  LARGE  TABLESPACE SUGARTS PAGESIZE 32 K  MANAGED BY AUTOMATIC STORAGE EXTENTSIZE 32 OVERHEAD 10.5 PREFETCHSIZE 32 TRANSFERRATE 0.14 BUFFERPOOL SUGARBP"
    db2 "CREATE USER TEMPORARY TABLESPACE SUGARXGTTTS IN DATABASE PARTITION GROUP IBMDEFAULTGROUP PAGESIZE 32K MANAGED BY AUTOMATIC STORAGE EXTENTSIZE 32 PREFETCHSIZE 32 BUFFERPOOL SUGARBP OVERHEAD 7.5 TRANSFERRATE 0.06 NO FILE SYSTEM CACHING"

    if [[ $(($FLAGS & $AS_BASE_DB)) -eq $AS_BASE_DB ]]; then
        __logging "${FUNCNAME[0]}" "$LINENO" "INFO" "Update DB config using LOGARCHMETH1 LOGRETAIN"
        db2 "UPDATE database configuration for $DB_NAME using LOGARCHMETH1 LOGRETAIN"

        __stop_db_app

        # 需要一次全量备份, 才能使用数据库
        __logging "${FUNCNAME[0]}" "$LINENO" "INFO" "backup db for the first time to use DB."
        db2 "backup db $DB_NAME to ${DBSOURCE_DIR} with 8 buffers buffer 8192 compress" || \
            __err "$LINENO" "Full DB backup failed."
        # 删除此次备份, 备份只为了能够使用这个数据库
        rm -rf "${DBSOURCE_DIR}/${DB_NAME}".0.*
    fi
}

backup_db()
{
    _print_msg "Backuping DB ${DB_NAME} ..."
    db2 "backup db ${DB_NAME} online to ${DBSOURCE_DIR} with 8 buffers buffer 8192 compress include logs without prompting"
    db2ckbkp -h "${DBSOURCE_DIR}"/"${DB_NAME}".*
}

db_restore() {
    _print_msg "Restoring DB"
    # DB_SOURCE_FILE_NAME=SALECONN.0.btit.DBPART000.20170804042104.001
    local _BACKUP_DB_TIMESTAMP=${DB_SOURCE_FILE_NAME%.*}
    local BACKUP_DB_TIMESTAMP=${_BACKUP_DB_TIMESTAMP##*.}
    local DB_SOURCE=${DB_SOURCE_FILE_NAME%%.*}

    __logging "${FUNCNAME[0]}" "$LINENO" "INFO" "DB_SOURCE_FILE_NAME: ${DB_SOURCE_FILE_NAME}"
    __logging "${FUNCNAME[0]}" "$LINENO" "INFO" "BACKUP_DB_TIMESTAMP: ${BACKUP_DB_TIMESTAMP}"
    __logging "${FUNCNAME[0]}" "$LINENO" "INFO" "DB_SOURCE: ${DB_SOURCE}"

    [[ -d "${DB_RESTORE_LOGPATH}" ]] && rm -rf "${DB_RESTORE_LOGPATH}"
    [[ -d "${DB_RESTORE_LOGTARGET}" ]] && rm -rf "${DB_RESTORE_LOGTARGET}"
    [[ -d "${DB_RESTORE_ARTIFACTS_DIR}" ]] && rm -rf "${DB_RESTORE_ARTIFACTS_DIR}"

    mkdir "${DB_RESTORE_LOGPATH}"
    mkdir "${DB_RESTORE_LOGTARGET}"
    mkdir "${DB_RESTORE_ARTIFACTS_DIR}"

    local IS_ERROR=0
    echo -e "\n
    [INFO] Starting REDIRECT RESTORE from backup (online) file
    for '${DB_SOURCE}' database
        into a database with a different name (${DB_NAME})"

        #This db command is going to generate an script with the name "db2_redirect_restore.clp"
        #under the artifacts folder. This script will be executed in the last step of this process.
        #As this script is the one that perform the restore action, we need to change some parameters
        #on it
        echo -e "\n[INFO] Generating 'Redirect Restore' script..."
        GENERATE_SCRIPT=$({

        if [ "$(db2ckbkp -H ${DBSOURCE_DIR}/${DB_SOURCE_FILE_NAME} | grep -c "(Offline)")" -ge 1 ]; then
            echo -e  "Offline image"
            db2 "restore db ${DB_SOURCE} from ${DBSOURCE_DIR} TAKEN AT ${BACKUP_DB_TIMESTAMP} INTO ${DB_NAME} REDIRECT generate script ${DB_RESTORE_ARTIFACTS_DIR}/db2_redirect_restore.clp without prompting"
        else
            echo -e  "Online image"
            db2 "restore db ${DB_SOURCE} from ${DBSOURCE_DIR} TAKEN AT ${BACKUP_DB_TIMESTAMP} INTO ${DB_NAME} LOGTARGET ${DB_RESTORE_LOGTARGET} NEWLOGPATH ${DB_RESTORE_LOGPATH} REDIRECT generate script ${DB_RESTORE_ARTIFACTS_DIR}/db2_redirect_restore.clp without prompting"
        fi

    } 2>&1)
    IS_ERROR=$?
    if [ $IS_ERROR -eq 0 ]; then
        echo -e "[INFO] 'Redirect Restore script' created - SUCCESS"
    else
        echo -e "[ERROR] Creation of 'Redirect Restore script' - FAILED
        ###\n${GENERATE_SCRIPT}\n###"
    fi

    # Step #1 - update table spaces for the DB_NAME
    if [ $IS_ERROR -eq 0 ]; then
        echo -e '\n[INFO] Update Step #1: patching tablespace paths #1 - to new values ...'
        VALUES_UPDATE=$({
        sed "s@/${DB_SOURCE}@/${DB_NAME}@g" "${DB_RESTORE_ARTIFACTS_DIR}/db2_redirect_restore.clp" > "${DB_RESTORE_ARTIFACTS_DIR}/db2_tmp_modified_script_0"
    } 2>&1)
    IS_ERROR=$?
    if [ $IS_ERROR -eq 0 ]; then
        echo -e '[INFO] Step #1 Update completed - SUCCESS'
        DB_SCRIPT_TO_RUN="${DB_RESTORE_ARTIFACTS_DIR}/db2_tmp_modified_script_0"
    else
        echo -e "[ERROR] Step #1: FAILED to complete
        ###\n${VALUES_UPDATE}\n###"
    fi
fi

# Step #2 - additional replace for paths with db name inlowercase
if [ $IS_ERROR -eq 0 ]; then
    echo -e '\n[INFO] Update Step #2: patching tablespace paths #2 - to new values (in lowercase)...'
    BACKUP_DB_NAME_LC=$(echo ${DB_SOURCE} | tr '[:upper:]' '[:lower:]')
    LOW_VALUES_UPDATE=$({
    sed "s@/${BACKUP_DB_NAME_LC}@/${DB_NAME}@g" "${DB_RESTORE_ARTIFACTS_DIR}/db2_tmp_modified_script_0" > "${DB_RESTORE_ARTIFACTS_DIR}/db2_tmp_modified_script_1"
} 2>&1)
IS_ERROR=$?
if [ $IS_ERROR -eq 0 ]; then
    echo -e '[INFO] Step #2 Update completed - SUCCESS'
    DB_SCRIPT_TO_RUN="${DB_RESTORE_ARTIFACTS_DIR}/db2_tmp_modified_script_1"
else
    echo -e "[ERROR] Step #2: FAILED to complete
    ###\n${LOW_VALUES_UPDATE}\n###"
fi
  fi

  # Step #3 - disable WITHOUT ROLLING FORWARD
  if [ $IS_ERROR -eq 0 ]; then
      echo -e "\n[INFO] Update Step #3: disabling WITHOUT ROLLING FORWARD piece in the 'Redirect Restore' script..."
      DISABLE_UPDATE=$({
      sed "s@WITHOUT ROLLING FORWARD@-- WITHOUT ROLLING FORWARD@g" "${DB_RESTORE_ARTIFACTS_DIR}/db2_tmp_modified_script_1" > "${DB_RESTORE_ARTIFACTS_DIR}/db2_tmp_modified_script_2"
  } 2>&1)
  IS_ERROR=$?
  if [ $IS_ERROR -eq 0 ]; then
      echo '[INFO] Step #3 Update completed - SUCCESS'
      DB_SCRIPT_TO_RUN="${DB_RESTORE_ARTIFACTS_DIR}/db2_tmp_modified_script_2"
  else
      echo -e "[ERROR] Step #3: FAILED to complete
      ###\n${DISABLE_UPDATE}\n###"
  fi
  fi

  # Step #4 - Enable StorageGroup paths for LobGroup creation
  if [ $IS_ERROR -eq 0 ]; then
      echo -e "\n[INFO] Update Step #4: enabling SET STOGROUP PATHS FOR IBMLOBGROUP piece in the 'Redirect Restore' script..."

      # Get Line Number of 1st Line of the DB command to be enabled
      UNCOMMENT_LINE_FROM=$(awk '/SET STOGROUP PATHS FOR IBMLOBGROUP/{print NR; exit}' "${DB_RESTORE_ARTIFACTS_DIR}/db2_tmp_modified_script_2" 2>&1)
      IS_ERROR=$?
      if [ $IS_ERROR -eq 0 ]; then
          # Double check if above Line was found Before continute further in this step
          if [[ ( -z "${UNCOMMENT_LINE_FROM}" ) || ( $UNCOMMENT_LINE_FROM -eq 0 ) ]]; then
              echo -e "\n[INFO] Line: '/SET STOGROUP PATHS FOR IBMLOBGROUP/'
              was NOT FOUND in file: '${DB_RESTORE_ARTIFACTS_DIR}/db2_tmp_modified_script_2'
              Above DB2 Command is NOT REQUIRED for this Restore process."
          else
              # Set the Line Number to uncomment TO
              UNCOMMENT_LINE_TO=$(( UNCOMMENT_LINE_FROM + 2 ))
              SCRIPT_UPDATE=$({
              sed "${UNCOMMENT_LINE_FROM},${UNCOMMENT_LINE_TO}s/-- //g" "${DB_RESTORE_ARTIFACTS_DIR}/db2_tmp_modified_script_2" > "${DB_RESTORE_ARTIFACTS_DIR}/db2_tmp_modified_script_3"
          } 2>&1)
          IS_ERROR=$?
          if [ $IS_ERROR -eq 0 ]; then
              echo -e "\n\t[INFO] Script Updated - SUCCESS"
              DB_SCRIPT_TO_RUN="${DB_RESTORE_ARTIFACTS_DIR}/db2_tmp_modified_script_3"
              # Get Path for LOB directory to be created/prepared
              LOB_DIR_LINE_NUM=$(( UNCOMMENT_LINE_FROM + 1 ))
              EXTRACT_LOB_DIR_PATH=".*'\(.*\)'.*$"
              LOB_DIR_TO_CREATE=$(sed "${LOB_DIR_LINE_NUM}s/${EXTRACT_LOB_DIR_PATH}/\1/g; ${LOB_DIR_LINE_NUM}!d" "${DB_RESTORE_ARTIFACTS_DIR}/db2_tmp_modified_script_3" 2>&1)
              IS_ERROR=$?
              if [ $IS_ERROR -eq 0 ]; then
                  echo -e "\n\t[INFO] Preparing LOB directory: '${LOB_DIR_TO_CREATE}'..."
                  # create directory
                  if [ ! -d "${LOB_DIR_TO_CREATE}" ]; then
                      echo -e "\t       Creating Directory: '${LOB_DIR_TO_CREATE}'..."
                      DIR_CREATE=$(mkdir -p "${LOB_DIR_TO_CREATE}" 2>&1)
                      IS_ERROR=$?
                      if [ $IS_ERROR -eq 0 ]; then
                          echo -e '\t       Done'
                      else # ERROR in directory creation
                          echo -e "\t       [ERROR] There was a problem with Directory Creation!
                          ###\n${DIR_CREATE}\n###"
                      fi
                      # clean directory contents
                  else
                      echo -e "\t       Cleaning directory's contents..."
                      DIR_CLEANUP=$(rm -rf "${LOB_DIR_TO_CREATE:?}/*" 2>&1)
                      IS_ERROR=$?
                      if [ $IS_ERROR -eq 0 ]; then
                          echo -e '\t       Done'
                      else # ERROR in directory cleanup
                          echo -e "\t       [ERROR] There was a problem with Directory Cleanup
                          ###\n${DIR_CLEANUP}\n###"
                      fi
                  fi
                  # end of directory preparation
              else # ERROR in obtaining directory to prepare
                  echo -e "\n\t[ERROR] There was a problem with extracting of LOB directory to be prepared
                  \t        from file: '${DB_RESTORE_ARTIFACTS_DIR}/db2_tmp_modified_script_3'
                  ###\n${LOB_DIR_TO_CREATE}\n###"
              fi
          else # ERROR in Script Update
              echo -e "[ERROR] There was problem with uncommenting
              lines: '${UNCOMMENT_LINE_FROM} - ${UNCOMMENT_LINE_TO}'
              from File: '${DB_RESTORE_ARTIFACTS_DIR}/db2_tmp_modified_script_2'
              ###\n${SCRIPT_UPDATE}\n###"
          fi
      fi
  else # ERROR in obtaining Line FROM
      echo -e "[ERROR] Error in getting line number
      for Line: 'SET STOGROUP PATHS FOR IBMLOBGROUP'
          from File: '${DB_RESTORE_ARTIFACTS_DIR}/db2_tmp_modified_script_2'
          ###\n${UNCOMMENT_LINE_FROM}\n###"
      fi

      if [ $IS_ERROR -eq 0 ]; then
          echo -e '\n[INFO] Step #4: Update completed - SUCCESS'
      else
          echo -e '[ERROR] Step #4: FAILED to complete'
      fi
  fi # END of Step 4

  # Final Check for ERRORs or run Redirect Restore Script
  if [ $IS_ERROR -eq 0 ]; then
      echo -e "\n[INFO] Running Redirect Restore
      script: '${DB_RESTORE_ARTIFACTS_DIR}/db2_tmp_modified_script_3'
      to restore backup into new database: '${DB_NAME}'..."
      db2 -tf "${DB_SCRIPT_TO_RUN}"
      RETURN_CODE=$?
      echo -e "[INFO] Done with return state (${RETURN_CODE})"
      db2 -v "rollforward db $DB_NAME to end of logs and stop overflow log path ($DB_RESTORE_LOGTARGET)"
      return $RETURN_CODE
  else
      echo -e "\n[ERROR] REDIRECT RESTORE from backup (online) FAILED to complete\n"
      #    delete_residual_files_from_cloning
      # DB2 ERROR Status is >= 4
      # Return a higher enough ERROR to not confuse it with DB2 warning
      return 225
  fi
}

independent_es_setup()
{
    # 需要独立 ES 数据
    _print_msg "Start ES server on port ${FTS_PORT}"

    # 设置 ES 配置文件, 保存到 TMP 目录下
    cat <<SYSCONFIG > "${TMP_DIR}"/elasticsearch.yml
cluster.name: "${INSTANCE_NAME}"
node.name: "${INSTANCE_NAME}"
path.conf: "/etc/elasticsearch/"
path.data: ${TMP_DIR}/es_data
path.work: ${TMP_DIR}/es_data
path.logs: ${TMP_DIR}/es_data
http.port: ${FTS_PORT}
SYSCONFIG

    # 启动独立ES, 删除实例时务必记得终止进程
    # BUILD_ID=dontKillMe 防止 jenkins kill
    local es_command="BUILD_ID=dontKillMe ${ES_BINARY} -Des.config=${TMP_DIR}/elasticsearch.yml -p ${TMP_DIR}/es.pid -d"
    __logging "${FUNCNAME[0]}" "$LINENO" "INFO" "setup an independent ES instance on port ${FTS_PORT}"
    __logging "${FUNCNAME[0]}" "$LINENO" "INFO" "$es_command"
    eval "${es_command}"
}

update_conf()
{
    _print_msg 'Update configuration'

    __logging "${FUNCNAME[0]}" "$LINENO" "INFO" "Update sugar instance config.php"

    # UNIQUE_KEY=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
    __logging "${FUNCNAME[0]}" "$LINENO" "INFO" "Generate UNIQUE_KEY: ${UNIQUE_KEY}"

    # config.php DB 配置
    __command_logging_and_exit "${FUNCNAME[0]}" "$LINENO" "sed 's!\^DB_HOST\^!${DB_HOST}!g; s!\^DB_NAME\^!${DB_NAME}!g; s!\^DB_ADMIN_USR\^!${DB_ADMIN_USR}!g; s!\^DB_ADMIN_PWD\^!${DB_ADMIN_PWD}!g; s!\^SERVER_HOSTNAME\^!${WEB_HOST}!g; s!\^INSTANCE_NAME\^!${INSTANCE_NAME}!g; s!\^FULL_HOST_NAME\^!${FULL_HOST_NAME}!g; s!\^UNIQUE_KEY\^!${UNIQUE_KEY}!g' ${PROJECT_DIR}/configs/config.php > ${WEB_DIR}/${INSTANCE_NAME}/config.php"

    # htaccess 配置
    __command_logging_and_exit "${FUNCNAME[0]}" "$LINENO" "sed 's/\^INSTANCE_NAME\^/${INSTANCE_NAME}/g' ./configs/htaccess > ${WEB_DIR}/${INSTANCE_NAME}/.htaccess"

    generate_config_override()
    {
        cat << CONFIG_OVERRIDE > ${WEB_DIR}/${INSTANCE_NAME}/genConfig.php
<?php
ini_set('display_errors', 1);
if(!defined('sugarEntry'))define('sugarEntry', true);

require_once('include/entryPoint.php');
include 'custom/install/SalesConnectInstaller.php';

\$sugar_config = array();
if (is_readable('config.php')) {
    include 'config.php';
}

// update config file
// 不能放到这里, 否则执行该脚本是数据库连接失败
//\$sugar_config['dbconfig']['db_host_name'] = "${DB_HOST}";
//\$sugar_config['dbconfig']['db_user_name'] = "${DB_ADMIN_PWD}";
//\$sugar_config['dbconfig']['db_password'] = "${DB_ADMIN_USR}";
//\$sugar_config['dbconfig']['db_name'] = "${DB_NAME}";
//\$sugar_config['host_name'] = "${FULL_HOST_NAME}";
//\$sugar_config['site_url'] = "${WEB_HOST}/${INSTANCE_NAME}";
//\$sugar_config['unique_key'] = "${UNIQUE_KEY}";
// ES
\$sugar_config['full_text_engine']['Elastic']['host'] = "${FTS_HOST}";
\$sugar_config['full_text_engine']['Elastic']['port'] = "${FTS_PORT}";

ksort(\$configs);
write_array_to_file("sugar_config", \$sugar_config, "config.php");

SalesConnectInstaller::executeTask('UpdateConfigFile');
CONFIG_OVERRIDE

        cd "${WEB_DIR}/${INSTANCE_NAME}" || __err "$LINENO" "${WEB_DIR}/${INSTANCE_NAME} folder does not exist."
        __command_logging_and_exit "${FUNCNAME[0]}" "$LINENO" "php genConfig.php"
    }
    generate_config_override
}

run_qrr()
{
    _print_msg 'Starting to run QRR...'

    declare -A qrr_scripts
    qrr_scripts[cacheCleanup]=""
    qrr_scripts[runFileMapBuildCache.php]=""
    qrr_scripts[runRebuildSugarLogicFunctions.php]=""
    qrr_scripts[runQuickRepair.php]="true true"
    qrr_scripts[showQuickRepairSQL.php]=""
    qrr_scripts[runRebuildSprites.php]=""
    qrr_scripts[runRepairRelationships.php]=""

    cd "${WEB_DIR}/${INSTANCE_NAME}" || __err "$LINENO" "SC instance directory [${WEB_DIR}/${INSTANCE_NAME}] not exists."

    for script in "${!qrr_scripts[@]}"; do
        [[ -f "${script}" ]] && rm -rf "${script}"
        [[ -f vendor/sugareps/SugarInstanceManager/templates/scripts/php/$script ]] \
            && cp vendor/sugareps/SugarInstanceManager/templates/scripts/php/$script ./
        __logging "${FUNCNAME[0]}" "$LINENO" "INFO" "php -f $script ${qrr_scripts[$script]}"
        php -f "$script" ${qrr_scripts[$script]} > "${TMP_DIR}/${script}.log" 2>&1
    done

    # QRR 结果将不作为安装流程的状态码
    curl ${WEB_HOST}
    return 0
}

run_dataloader()
{
    _print_msg "Run dataloader..."

    __logging "${FUNCNAME[0]}" "$LINENO" "INFO" "Run hook [run_dataloader]"

    # DATALOADER_DIR 定义在 install.py
    cd "${DATALOADER_DIR}" || __err "$LINENO" "Dataloader folder [${DATALOADER_DIR}] not exists."

    [[ -f config.php ]] || __err "$LINENO" "Current directory [${PWD}] is not a validated dataloader folder."

    cat <<CONFIG > config.php
<?php

\$config = array(

    // DB settings
    'db' => array(
        'type' => 'db2', // mysql or db2
        'host' => '${DB_HOST}',
        'port' => '${DB_PORT}',
        'username' => '${DB_ADMIN_USR}',
        'password' => '${DB_ADMIN_PWD}',
        'name' => '${DB_NAME}',
    ),

    // default bean field/values used by Utils_Db::createInsert()
    'bean_fields' => array(
        'created_by' => '1',
        'date_entered' => '2012-01-01 00:00:00',
        'modified_user_id' => '1',
        'date_modified' => '2012-01-01 00:00:00',
    ),

    // sugarcrm
    'sugarcrm' => array(
        // full path of the installed sugarcrm instance
        'directory' => '${WEB_DIR}/${INSTANCE_NAME}',
    ),

);
CONFIG
    php populate_SmallDataset.php
}

run_avl()
{
    _print_msg 'Importing AVL...'

    cd "${WEB_DIR}/${INSTANCE_NAME}/custom/cli" || __err "$LINENO" "SC instance directory [${WEB_DIR}/${INSTANCE_NAME}] not exists."

    _green_echo "Importing avl.csv..."
    php cli.php task=Avlimport file="${WEB_DIR}/${INSTANCE_NAME}"/custom/install/avl.csv idlMode=true

    for avl_file in ${WEB_DIR}/${INSTANCE_NAME}/custom/install/avl/*.csv; do
        _green_echo "Importing ${avl_file}..."
        php cli.php task=Avlimport file="${avl_file}"
    done

    php cli.php task=AVLRebuildFile
}

run_unittest()
{
    _print_msg 'Starting to run PHP UNITTEST...'
    cd "${WEB_DIR}/${INSTANCE_NAME}"/tests

    vendor_unit="${WEB_DIR}"/"${INSTANCE_NAME}"/vendor/bin/phpunit
    if [[ -f "${vendor_unit}" ]]; then
        php "${vendor_unit}"
    else
        phpunit
    fi

    # 总是返回 0
    return 0
}

before_install()
{
    _print_msg 'Run Hook [before install]'

    # custome ES instance
    [[ $(($FLAGS & $INDEPENDENT_ES)) -eq $INDEPENDENT_ES ]] && independent_es_setup

    [[ $(($FLAGS & $INIT_DB)) -eq $INIT_DB ]] && init_db

    # restore database
    # RESTORE_INSTALL 为0, 需要使用 FULL_INSTALL 做比较
    # 复制安装方式
    if [[ $(($FLAGS & $FULL_INSTALL)) -ne $FULL_INSTALL ]]; then
        __logging "${FUNCNAME[0]}" "$LINENO" "INFO" "The instance is installed from restore"

        __logging "${FUNCNAME[0]}" "$LINENO" "INFO" "Running [db_restore]"
        db_restore

        __logging "${FUNCNAME[0]}" "$LINENO" "INFO" "Running [update_conf]"
        update_conf

        __logging "${FUNCNAME[0]}" "$LINENO" "INFO" "Running [run_qrr]"
        run_qrr
    fi

    # 此处需要有一条语句, 防止上面的判断导致函数退出返回非0值
    echo ''
}

install_bp()
{
    _print_msg "Starting to install BP instance..."

    local bp_instance_name="${INSTANCE_NAME}_bp"
    local bp_instance_web="${WEB_DIR}/${bp_instance_name}"
    local sc4bp_script_path=''

    if [[ $(($FLAGS & $SOURCE_FROM_GIT)) -eq $SOURCE_FROM_PACKAGE ]]; then
        __command_logging_and_exit "${FUNCNAME[0]}" "$LINENO" "unzip -o ${TMP_DIR}/${base_package} \"scripts/sc4bp/*\" -d ${TMP_DIR}/ > /dev/null"
        sc4bp_script_path="${TMP_DIR}/scripts/sc4bp"
    else
        sc4bp_script_path="${GIT_DIR}/ibm/upgrade/default/scripts/sc4bp"
    fi

    __logging "${FUNCNAME[0]}" "$LINENO" "INFO" "sc4bp_script_path: ${sc4bp_script_path}"

    [[ -d "${bp_instance_web}" ]] && rm -Rf "${bp_instance_web}"
    cp -rp "${WEB_DIR}/${INSTANCE_NAME}" "${bp_instance_web}"

    # 修正 .htaccess 文件
    __command_logging_and_exit "${FUNCNAME[0]}" "$LINENO" "sed 's^/${INSTANCE_NAME}^/${bp_instance_name}^g' ${WEB_DIR}/${INSTANCE_NAME}/.htaccess > ${bp_instance_web}/.htaccess"

    # 删除 cache 缓存文件
    if [ -d "${bp_instance_web}/cache" ]; then
        rm -Rf "${bp_instance_web}/cache"
        ln -s "${WEB_DIR}/${INSTANCE_NAME}/cache" "${bp_instance_web}/cache"
    fi

    cat <<ORDER > ${sc4bp_script_path}/sc4bp_order.php
<?php
include "metadata.php";
foreach(\$orderedFiles as \$scripts) {
    echo \$scripts . "\n";
}
ORDER

    cd "${bp_instance_web}"
    for script in $(php ${sc4bp_script_path}/sc4bp_order.php); do
        _green_echo "Run sc4bp script [${script}]"
        __command_logging_and_exit "${FUNCNAME[0]}" "$LINENO" "cp -r ${sc4bp_script_path}/${script} ${bp_instance_web}/${script}"
        __logging "${FUNCNAME[0]}" "$LINENO" "INFO" "run sc4bp script: ${bp_instance_web}/${script}"
        php ${script}
        # __logging "${FUNCNAME[0]}" "$LINENO" "INFO" "php ${bp_instance_web}/${script}"
    done

    return 0
}

setup_webide()
{
    local sc_webide_path=${HOME}/www/sc_webide
    [[ ! -d ${sc_webide_path} ]] \
        && echo 'no web ide found.' \
        &&  return 0

    cp -r "${sc_webide_path}" "${WEB_DIR}/${INSTANCE_NAME}"

    IN_WEBIDE=${WEB_DIR}/${INSTANCE_NAME}/sc_webide
    IN_WEBIDE_URL="${WEB_HOST}/${INSTANCE_NAME}/sc_webide"

    sed -i "s^#path#^"${IN_WEBIDE}"^g" "${IN_WEBIDE}"/config.php
    sed -i "s^#url#^"${IN_WEBIDE_URL}"^g" "${IN_WEBIDE}"/config.php

    mkdir "${IN_WEBIDE}"/workspace && ln -s  "${WEB_DIR}/${INSTANCE_NAME}" "${IN_WEBIDE}/workspace/sc"
}

generate_es_data()
{
    _print_msg "Generating ES data..."
    __logging "${FUNCNAME[0]}" "$LINENO" "INFO" "Run hook [generate_es_data]"

    cd "${WEB_DIR}/${INSTANCE_NAME}"

    cat << 'SCHEDULE_ES_DATA' > schedule_search_index.php
<?php
if(!defined('sugarEntry'))define('sugarEntry', true);
require_once('include/entryPoint.php');
$clearData = true; // will erase existing index data when true
$modules = array(); // will pull all active modules when empty, or you can specify module names
$indexerClass = 'SugarSearchEngineFullIndexer';
SugarAutoLoader::requireWithCustom('include/SugarSearchEngine/SugarSearchEngineFullIndexer.php');
if (class_exists(SugarAutoLoader::customClass($indexerClass))) {
    $indexerClass = SugarAutoLoader::customClass($indexerClass);
}
$indexer = new $indexerClass();
$indexer->initiateFTSIndexer($modules, $clearData);
$_REQUEST['enabled_modules'] = 'Accounts,Calls,Cases,Contacts,Documents,Leads,Meetings,Notes,ibm_RevenueLineItems,Opportunities,Users,Tasks,Employees';
require_once('modules/Home/UnifiedSearchAdvanced.php');
$unifiedSearchAdvanced = new UnifiedSearchAdvanced();
$unifiedSearchAdvanced->saveGlobalSearchSettings();
SCHEDULE_ES_DATA

    php schedule_search_index.php
    php cron.php
}

after_install()
{
    # 升级补丁包 如果与 git 比较结果为0, 则是包安装
    [[ $(($FLAGS & $SOURCE_FROM_GIT)) -eq $SOURCE_FROM_PACKAGE ]] \
        && __logging "${FUNCNAME[0]}" "$LINENO" "INFO" "Upgrade package" \
        && upgrade_package

    # BP instance
    [[ $(($FLAGS & $BP_INSTANCE)) -eq $BP_INSTANCE ]] \
        && __logging "${FUNCNAME[0]}" "$LINENO" "INFO" "Install BP instance" \
        && install_bp

    # run dataloader
    [[ $(($FLAGS & $DATA_LOADER)) -eq $DATA_LOADER ]] \
        && __logging "${FUNCNAME[0]}" "$LINENO" "INFO" "Import DataLoader" \
        && run_dataloader

    # run AVL
    [[ $(($FLAGS & $AVL)) -eq $AVL ]] \
        && __logging "${FUNCNAME[0]}" "$LINENO" "INFO" "Import AVL" \
        && run_avl

    # 是否要跑 QRR, 应该在数据库备份之前
    [[ $(($FLAGS & $QRR)) -eq $QRR ]] \
        && __logging "${FUNCNAME[0]}" "$LINENO" "INFO" "Run QRR" \
        && run_qrr

    # 备份数据库
    [[ $(($FLAGS & $AS_BASE_DB)) -eq $AS_BASE_DB ]] \
        && __logging "${FUNCNAME[0]}" "$LINENO" "INFO" "Backup database" \
        && backup_db

    # run UnitTest
    [[ $(($FLAGS & $UT)) -eq $UT ]] \
        && __logging "${FUNCNAME[0]}" "$LINENO" "INFO" "Run UnitTest" \
        && run_unittest

    # run ES data
    [[ $(($FLAGS & $INDEPENDENT_ES)) -eq $INDEPENDENT_ES ]] && generate_es_data

    setup_webide

    _green_echo "Finish"
}

__main()
{
    local HOOK_NAME="${1}"
    shift

    [[ $(($FLAGS & $DEBUG)) -eq $DEBUG ]] && set -x

    # 修改为了从 setup.py 获取
    [[ -f "${CUS_INSTALL_HOOK}" ]] && . "${CUS_INSTALL_HOOK}"

    "${HOOK_NAME}" "$@"
}

readonly -f __main
readonly -f __logging
readonly -f __err
readonly -f __command_logging_and_exit

__main "$@"
