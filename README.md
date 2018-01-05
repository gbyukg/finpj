# CLI

The project can be run from CLI directly.

``` sh
install.py install \
 --conf-section dev01
 --full-install/--restore-install \
 --db-source saleconn \
 --instance-name 68 \
 --instance-db-name DB_68 \
 --init-db \
 --keep-alive 5 \
 --git \
 --source-code 32599 32601 \
 --[no-]data-loader \
 --[no-]avl \
 --[no-]ut \
 --independent-es
```

# Jenkins Job

The scrennshot of the Jenkins job

![Alt text](jenkins_job.png?raw=true "Jenkins Job")
