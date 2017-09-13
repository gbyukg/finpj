#!/usr/bin/env bash

trap 'ERRTRAP $LINENO' ERR

. "${HOME}"/sqllib/db2profile

clean_file_dir=${1:-$(date +%Y-%m-%d)}
readonly clean_dir=${HOME}/tmp/"${clean_file_dir}"
readonly web_dir=${HOME}/www/sales

red_echo()
{
    printf "\n\e[31m%s\e[0m\n" "$@"
}

ERRTRAP()
{
    red_echo "[LINE:$1] Error: Command or function exited with status $?"
}

drop_db()
{
    local db_name=${1}
    printf "Drop database %s ...\n" "${db_name}"

    for app in $(db2 list applications for database ${db_name} | awk '/[0-9]/{print $3}')
    do
        db2 "force application ( $app )"
    done
    db2 "DROP DATABASE ${db_name}" # drop the previously existing database if it exists

    if [[ $? -ne 0 ]]; then
        db2 connect to "${db_name}" && \
        db2 quiesce database immediate force connections && \
        db2 unquiesce database && \
        db2 connect reset && \
        db2 deactivate db "${db_name}" && \
        db2 "DROP DATABASE ${db_name}" # drop the previously existing database if it exists
    fi
}

clean_logs()
{
    > $HOME/www/logs/php_errors.log
    > $HOME/www/logs/access_log
    > $HOME/www/logs/error_log
}

[[ ! -d "${clean_dir}" ]] && echo "Done" && exit 0
echo "Drop instances in [${clean_file_dir}]"

cd "${clean_dir}"

db2 list db directory | grep 'Database alias' | cut -d'=' -f2 > db_installed

for del_file in *; do
    if [[ -d "${web_dir}/${del_file}" ]]; then
        printf "\nRemoving %s ...\n" "${del_file}"
    else
        continue
    fi

    cat << 'GET_DB_NAME' > "${web_dir}/${del_file}/get_db_name.php"
<?php
include "config.php";
echo $sugar_config['dbconfig']['db_name'];
GET_DB_NAME

    db_name=$(php ${web_dir}/${del_file}/get_db_name.php)

    if [[ -n $db_name && $(grep $db_name db_installed; echo $?) -eq 0 ]]; then
        drop_db $db_name
    fi

    # 如果安装实例的时候使用了单独的 ES, 则kill掉进程
    if [[ -f "${clean_dir}/${del_file}"/es.pid ]]; then
        echo "Kill ES process"
        kill -KILL "$(cat ${clean_dir}/${del_file}/es.pid)"
    fi

    [[ -d "${web_dir}/${del_file}" ]] && rm -rf "${web_dir}/${del_file}" > /dev/null 2>&1
    [[ -d "${web_dir}/${del_file}_bp" ]] && rm -rf "${web_dir}/${del_file}_bp" > /dev/null 2>&1
done

clean_logs

# for i in $(grep 'Database alias' db | cut -d'=' -f2 | cut -d'_' -f2); do [[ -d $i ]] || echo $i; done
# for i in 2017-*; do for j in $i; do ls $j; done done

