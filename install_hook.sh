#!/usr/bin/env bash

set -o nounset

SCRIPT_NAME=$(basename "$0")

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
    local msg=""

    msg=$(2>&1 eval "${cmd}")
    return_code="$?"

    if [[ 0 -eq "${return_code}" ]]; then
        #[[ "$DEBUG" -eq 1 ]] && echo "${msg}"
        __logging "$FUN_NAME" "$LINE_NO" "SH-COMMAND:${return_code}" "${cmd}"
    else
        echo "SH-COMMAND[${return_code}] ${cmd}; Message: [${msg}]"
        __logging "$FUN_NAME" "$LINE_NO" "SH-COMMAND:${return_code}" "${cmd}; Message: [${msg}]"
        exit 1
    fi
}

build_code()
{
    __logging "${FUNCNAME[0]}" "$LINENO" "INFO" "Run hook [build_code]"

    echo "building code..."
    __command_logging_and_exit \
        "${FUNCNAME[0]}" "$LINENO" \
        "cd ${GIT_DIR}/build/rome && php build.php -clean -cleanCache -flav=ult -ver='7.1.5' -dir=sugarcrm -build_dir=${BUILD_DIR}"

    [[ -d "${WEB_DIR}/${INSTANCE_NAME}" ]] && __command_logging_and_exit "${FUNCNAME[0]}" "$LINENO" "rm -rf ${WEB_DIR}/${INSTANCE_NAME}"
    __command_logging_and_exit "${FUNCNAME[0]}" "$LINENO" "mv ${BUILD_DIR}/ult/sugarcrm ${WEB_DIR}/${INSTANCE_NAME}"
}

after_prepare_code()
{
    # update composer
    echo "update composer..."
    cd "${GIT_DIR}"/sugarcrm || exit 1
    COMPOSER_DISABLE_XDEBUG_WARN=1 composer install
}

prepare_source_from_pr()
{
    echo "Preparing git..."
    echo ''

    local PR_NUMS=($@)
    local git_refs="git@github.com:sugareps/Mango.git +refs/heads/*:refs/remotes/sugareps/*"
    local check_ref=''
    local merge_ref=''
    local middle_ref=''

    cd "${GIT_DIR}" || __err "$LINENO" "Git directory [${GIT_DIR}] not exists."

    __command_logging_and_exit "${FUNCNAME[0]}" "$LINENO" "cd ${GIT_DIR}"
    __command_logging_and_exit "${FUNCNAME[0]}" "$LINENO" "git rev-parse --git-dir"

    for par in "${PR_NUMS[@]}"; do
        # pr sugareps 12345
        # br sugareps ibm_r40
        IFS=:
        info=($par)
        unset IFS

        if [[ "X${info[0]}" == 'Xpr' ]]; then
            git_refs="${git_refs} +refs/pull/*/head:refs/remotes/${info[1]}/pr/*"
            middle_ref='pr'
        else
            git_refs="${git_refs} +refs/heads/*:refs/remotes/${info[1]}/*"
            middle_ref=''
        fi

        if [[ -z "${check_ref}" ]]; then
            check_ref="${info[1]}/${middle_ref}/${info[2]}"
        else
            merge_ref="${merge_ref} ${info[1]}/${middle_ref}/${info[2]}"
        fi
    done

    __command_logging_and_exit "${FUNCNAME[0]}" "$LINENO" "git reset --hard"
    __command_logging_and_exit "${FUNCNAME[0]}" "$LINENO" "git clean -fdx"

    __command_logging_and_exit "${FUNCNAME[0]}" "$LINENO" "git fetch ${git_refs}" #|| __err "$LINENO" "git fetch failed."
    __command_logging_and_exit "${FUNCNAME[0]}" "$LINENO" "git checkout -f ${check_ref}"
    [[ -n "${merge_ref}" ]] && __command_logging_and_exit "${FUNCNAME[0]}" "$LINENO" "git merge --squash ${merge_ref}"

    __command_logging_and_exit "${FUNCNAME[0]}" "$LINENO" "git submodule sync"
    __command_logging_and_exit "${FUNCNAME[0]}" "$LINENO" "git submodule update --init --recursive"

    after_prepare_code
}

init_db()
{
    echo "Creating database ${DB_NAME}..."

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

    if [[ "${AS_BASE_DB}" == 'True' ]]; then
        db2 "UPDATE database configuration for $DB_NAME using LOGARCHMETH1 LOGRETAIN"
        # 需要一次全量备份, 才能使用数据库
        db2 "backup db $DB_NAME to ${DBSOURCE_DIR}" || \
            __err "$LINENO" "Full DB backup failed."
        # 删除此次备份, 备份只为了能够使用这个数据库
        rm -rf "${DB_NAME}*"
    fi
    exit 1
}

backup_db()
{
    echo "Backuping DB ${DB_NAME} ..."
    db2 "backup db ${DB_NAME} online to ${DBSOURCE_DIR} without prompting"
}

db_restore()
{

    echo "Restoring DB from [${DB_SOURCE}] into [${DB_NAME}]..."
    __command_logging_and_exit "${FUNCNAME[0]}" "$LINENO" "db2 restore db ${DB_SOURCE} from ${DBSOURCE_DIR} into ${DB_NAME} without prompting"
    __command_logging_and_exit "${FUNCNAME[0]}" "$LINENO" "db2 rollforward database ${DB_NAME} complete"
}

run_qrr()
{
    echo 'Starting to run QRR...'

    local qrr_scripts[0]='cacheCleanup'
    local qrr_scripts[1]='runFileMapBuildCache.php'
    local qrr_scripts[2]='runRebuildSugarLogicFunctions.php'
    local qrr_scripts[3]='runQuickRepair.php'
    local qrr_scripts[4]='showQuickRepairSQL.php'
    local qrr_scripts[5]='runRebuildJSGroupings.php'
    local qrr_scripts[6]='runRebuildSprites.php'
    local qrr_scripts[7]='runRepairRelationships.php'

    cd "${WEB_DIR}/${INSTANCE_NAME}" || __err "$LINENO" "SC instance directory [${WEB_DIR}/${INSTANCE_NAME}] not exists."

    for script in "${qrr_scripts[@]}"; do
        [[ -f "${script}" ]] && rm -rf "${script}"
        cp vendor/sugareps/SugarInstanceManager/templates/scripts/php/$script ./
        php -f "$script" 2>&1 | tee qrr_${script}_$$.out
    done
}

update_conf()
{
    echo 'Update configfiles...'

    # config.php DB 配置
    __command_logging_and_exit "${FUNCNAME[0]}" "$LINENO" "sed 's/\^DB_HOST\^/${DB_HOST}/g; s/\^DB_NAME\^/${DB_NAME}/g; s/\^DB_ADMIN_USR\^/${DB_ADMIN_USR}/g; s/\^DB_ADMIN_PWD\^/${DB_ADMIN_PWD}/g' ${PROJECT_DIR}/configs/config.php > ${WEB_DIR}/${INSTANCE_NAME}/config.php"

    # htaccess 配置
    __command_logging_and_exit "${FUNCNAME[0]}" "$LINENO" "sed 's/\^INSTANCE_NAME\^/${INSTANCE_NAME}/g' ./configs/htaccess > ${WEB_DIR}/${INSTANCE_NAME}/.htaccess"
}

run_avl()
{
    echo 'Importing AVL...'

    cd "${WEB_DIR}/${INSTANCE_NAME}/custom/cli" || __err "$LINENO" "SC instance directory [${WEB_DIR}/${INSTANCE_NAME}] not exists."

    green_echo "Importing avl.csv..."
    php cli.php task=Avlimport file="${WEB_DIR}/${INSTANCE_NAME}"/custom/install/avl.csv idlMode=true

    for avl_file in ${WEB_DIR}/${INSTANCE_NAME}/custom/install/avl/*.csv; do
        green_echo "Importing ${avl_file}..."
        php cli.php task=Avlimport file="${avl_file}"
    done

    php cli.php task=AVLRebuildFile
}

run_dataloader()
{
    echo "Run dataloader..."

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

before_install_restore()
{
    echo 'before_install_restore'
    db_restore
    update_conf
    run_qrr
}

after_install_restore()
{
    echo 'after_install_restore'
}

before_install_sbs()
{
    [[ "${INIT_DB}" == 'True' ]] && init_db
}

after_install_sbs()
{
    # run dataloader
    [[ "${DATA_LOADER}" == 'True' ]] && run_dataloader

    # run AVL
    [[ "${AVL}" == 'True' ]] && run_avl

    # 是否要跑 QRR, 应该在数据库备份之前
    [[ "${QRR_AFTER_INSTALL}" == 'True' ]] && run_qrr

    [[ "${AS_BASE_DB}" == 'True' ]] && backup_db
}

__main()
{
    local HOOK_NAME="${1}"
    shift

    DEBUG=${DEBUG-'False'}
    [[ "${DEBUG}" == 'True' ]] && set -x

    # 修改为了从 setup.py 获取
    [[ -f "${CUS_INSTALL_HOOK}" ]] && . "${CUS_INSTALL_HOOK}"

    "${HOOK_NAME}" "$@"
}

readonly -f __main
readonly -f __logging
readonly -f __err
readonly -f __command_logging_and_exit

__main "$@"
