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
    # __command_logging_and_exit \
        # "$FUNCNAME" "$LINENO" \
        # "cd ${GIT_DIR}/build/rome && php build.php -clean -cleanCache -flav=ult -ver='7.1.5' -dir=sugarcrm -build_dir=${BUILD_DIR}"

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

    #__command_logging_and_exit "${FUNCNAME[0]}" "$LINENO" "git fetch ${git_refs}" #|| __err "$LINENO" "git fetch failed."
    __command_logging_and_exit "${FUNCNAME[0]}" "$LINENO" "git checkout -f ${check_ref}"
    [[ -n "${merge_ref}" ]] && __command_logging_and_exit "${FUNCNAME[0]}" "$LINENO" "git merge --squash ${merge_ref}"

    __command_logging_and_exit "${FUNCNAME[0]}" "$LINENO" "git submodule sync"
    __command_logging_and_exit "${FUNCNAME[0]}" "$LINENO" "git submodule update --init --recursive"

    after_prepare_code
}

backup_db()
{
    db2 "UPDATE database configuration for $DBNAME using LOGARCHMETH1 LOGRETAIN"
    db2 backup db taq to /home/btit/db2backup/
    db2 backup db taq online to /home/btit/db2backup/ without prompting
    db2 restore db taq taken at 20170726100035 into zzlzhang without prompting
    db2 rollforward db zzlzhang
}

db_restore()
{
    # DB_SOURCE
    # db2 restore db saleconn from ${DBSOURCE_DIR} taken at 20170802130539 into DB_1 without prompting
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

    __command_logging_and_exit "${FUNCNAME[0]}" "$LINENO" "cd ${WEB_DIR}/${INSTANCE_NAME}"

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
    # echo $@
    echo 'before_install_sbs'
}

after_install_sbs()
{
    echo 'after_install_sbs'
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

update_conf
exit 0

__main "$@"
