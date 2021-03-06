#!/bin/sh
# fast to hadoop, AVOID WASTE TIME TO INSTALL TOO MANY MANY ENV
# 支持分布式(包括单机伪分布式，至少一台)，高可用方式（至少三台）
SCRIPT_PATH=$(cd `dirname $0`;pwd)
cd $SCRIPT_PATH
#echo "SCRIPT_PATH:$SCRIPT_PATH"
EXAMPLE="sh $0 hadoop|hive|spark"
_DEBUG_MODE=false
jdk_tgz_url='http://download.oracle.com/otn-pub/java/jdk/8u131-b11/d54c1d3a095b4ff2b6607d096fa80163/jdk-8u131-linux-x64.tar.gz'
hadoop_tgz_url="https://archive.apache.org/dist/hadoop/common/hadoop-2.10.1/hadoop-2.10.1.tar.gz"
hive_tgz_url="https://archive.apache.org/dist/hive/hive-2.3.9/apache-hive-2.3.9-bin.tar.gz"
mysql_jar_url="https://repo1.maven.org/maven2/mysql/mysql-connector-java/5.1.49/mysql-connector-java-5.1.49.jar"
spark_tgz_url="https://archive.apache.org/dist/spark/spark-2.4.8/spark-2.4.8-bin-without-hadoop.tgz"

function LOG() {
    echo -e "[ `date +"%F %T"` ][ INFO | $* ]" | tee -a $SCRIPT_PATH/install.log 
}
function LOG_INFO() {
    echo -e "[ `date +"%F %T"` ][ INFO | $* ]" | tee -a $SCRIPT_PATH/install.log
}
function LOG_ERROR() {
    echo -e "[ `date +"%F %T"` ][ ERROR | $* ]" | tee -a $SCRIPT_PATH/install.log
    #break
}
function try_wget() {
    cd $SCRIPT_PATH
    wget $1
    if [ $? -ne 0 ];then
        LOG_ERROR "download $1 failed, exit"
        exit -1
    fi
}
function is_empty() {
    if [ "x$1" == "x" ];then 
        LOG_ERROR "check name is empty"
        exit -1
    else 
        value=`eval echo "$"$1`
        if [ "x$value" == "x" ];then
            LOG_ERROR "$1 is empty"
            exit -1
        fi
    fi
    if [ "x$2" != "x" ]; then 
        LOG "$1 => $value"
    fi
}
function execute_and_print_order() {
    if [ "x$3" == "xtrue" ];then 
        LOG "[ EXECUTE | ssh $1 | $2 ]"
    else
        LOG "[ EXECUTE | ssh $1 | $2 ]" > /dev/null
    fi
    ssh $1 "$2" 2>&1 | tee -a $SCRIPT_PATH/install.log
    return ${PIPESTATUS[0]}
}

function execute_and_check_order() {
    execute_and_print_order "$@"
    if [ $? -ne 0 ];then 
        LOG_ERROR "ERROR interruped!!!!"
        exit -1
    fi
}

function source_config() { 
    source $SCRIPT_PATH/fast_install_config.sh
    if [ "$YARN_RESOURCEMANAGER" == "localhost" ]; then 
        YARN_RESOURCEMANAGER="0.0.0.0"
    fi
}

function install_java() {
    is_empty JAVA_HOME
    ms=$(echo $* | tr " " "\n" |tr "," "\n"| grep -v '^$' | sort -u)
    if [ "x$ms" == "x" ];then
        ms=$(echo $HDFS_DATANODE,$HDFS_NAMENODE | tr " " "\n" |tr "," "\n"| grep -v '^$' | sort -u)
        LOG "(default) install java on hadoop machine"
    fi
    cd $SCRIPT_PATH
    jdk_name=$(ls jdk-8u*-linux-x64.tar.gz 2>/dev/null | head -1)
    if [ "x$jdk_name" == "x" ];then
        LOG wget -c --header "Cookie: oraclelicense=accept-securebackup-cookie" $jdk_tgz_url
        wget -c --header "Cookie: oraclelicense=accept-securebackup-cookie" $jdk_tgz_url
        if [ $? -ne 0 ]; then 
            LOG_ERROR "download jdk failed"
            rm -f jdk-8u*.tar.gz
            exit -1
        fi
        jdk_name=$(basename $jdk_tgz_url)
    fi
    if [ ! -f $jdk_name ];then 
        LOG_ERROR "file not find"
        exit -1
    fi
    echo "\
export JAVA_HOME=$JAVA_HOME
export PATH=\$PATH:\$JAVA_HOME/bin
export CLASSPATH=.:\$JAVA_HOME/lib:\$JAVA_HOME/lib/tools.jar
"  > java.sh
    LOG "WILL INSTALL java at "$ms" .."
    for machine in $ms
    do
        echo $machine
        cd $SCRIPT_PATH
        execute_and_check_order $machine "mkdir -p $INSTALL_PATH/"
        scp java.sh $machine:/etc/profile.d/java.sh
        scp $jdk_name $machine:$INSTALL_PATH/$jdk_name
        execute_and_check_order $machine "
            # clean env
            rpm -qa | grep java | xargs -i rpm -e --nodeps {}
            rm -rf $JAVA_HOME
            install_path=\"`dirname $JAVA_HOME`\"
            mkdir -p \$install_path
            # unzip file
            cd $INSTALL_PATH/
            tar --no-same-owner -zxf $jdk_name -C \$install_path/
            rm -rf $jdk_name
            # rename dir
            mv \$install_path/jdk1.8.* $JAVA_HOME
            
            " false
    done
    rm -rf java.sh
}
function check_hadoop_env() {
    
    for x in JAVA_HOME HADOOP_HOME HDFS_NAMENODE HDFS_DATANODE HADOOP_HA
    do
        is_empty $x out
    done
    #if [ ! -d $JAVA_HOME ];then
    #    LOG_ERROR "need install java or fix var JAVA_HOME"
    #    exit -1
    #fi
}
# for send to slave
# replace_line_func <filename> <old_string> <new_string> <default line number if not find, defalt -1 is append to end of file>
replace_line_func="
function replace_line_func() {
    filepath=\$1
    old_line=\$2
    new_line=\$3
    if [ \$# == 4 ]; then 
        default_linenum=\${4}
    else
        default_linenum=-1
    fi
    
    #echo default_linenum \$default_linenum
    #echo \"\\\$@=>\"\$@
    linenum=\$(grep -n \"\$old_line\" \"\$filepath\" | head -n 1 | cut -d':' -f1)
    #echo linenum \$linenum
    if [ \"x\$linenum\" != \"x\" ]; then 
        sed -i \"\${linenum}c \${new_line}\" \"\$filepath\"
    else
        if [ \"x\${default_linenum}\" != 'x-1' ]; then 
            sed -i \"\${default_linenum}a \$new_line\" \"\$filepath\"
        else
            sed -i \"\$a \$new_line\" \"\$filepath\"
        fi
    fi
    return $?
}
"
replace_config_func="
def replace_config_func(file_path, old_str, new_str):
    text = None
    with open(file_path) as f:
        text = f.read()
    with open(file_path,\"w\") as f:
        f.write(text.replace(old_str,new_str))
"
function install_hadoop() {
    check_hadoop_env
    ssh_login_free_trust
    hadoop_config
    cd $SCRIPT_PATH
    hadoop_tgz=$(ls hadoop-2.*.tar.gz 2>/dev/null | head -1)
    if [ "x$hadoop_tgz" == "x" ];then 
        try_wget $hadoop_tgz_url
        hadoop_tgz=$(basename $hadoop_tgz_url)
    fi
    if [ ! -f $hadoop_tgz ];then 
        LOG_ERROR "hadoop install file not find"
        exit -1
    fi
    LOG "==========START TO DEPLOY=========="
    if [ "x$HADOOP_HA" == "xtrue" ];then
        ms=$(echo "$HDFS_NAMENODE,$HDFS_DATANODE,$HDFS_HA_NAMENODE_2" | tr ',' '\n' | sort -u)
    else 
        ms=$(echo "$HDFS_NAMENODE,$HDFS_DATANODE" | tr ',' '\n' | sort -u)
    fi
    for machine in $ms
    do
        LOG "$machine start.."
        cd $SCRIPT_PATH
        execute_and_check_order $machine "
        for datadir in ${HDFS_DATANODE_DATA_DIR/,/ }
        do
            if [ -e \$datadir ];then 
                rm -rf \$datadir/*
                echo \"clean dir \$datadir\"
            fi
        done
        
        mkdir -p $INSTALL_PATH/ ${HDFS_DATANODE_DATA_DIR/,/ }
        "
        
        scp -q $hadoop_tgz $machine:$INSTALL_PATH/$hadoop_tgz
        execute_and_check_order $machine "
            # clean env first
            rm -rf $HADOOP_HOME
            
            base_path=\"`dirname $HADOOP_HOME`\"
            mkdir -p \$base_path
            # unzip file
            cd $INSTALL_PATH
            tar --no-same-owner -zxf $hadoop_tgz -C \$base_path/
            if [ \$? != 0 ];then
              echo '$machine tar $hadoop_tgz failed'
              exit -1
            fi
            rm -rf $INSTALL_PATH/$hadoop_tgz
            
            # rename dir
            mv \$base_path/${hadoop_tgz%\.tar\.gz} $HADOOP_HOME

            if [ ! -d \"$HADOOP_HOME\" ];then 
                echo '$machine $HADOOP_HOME not exit'
                exit -1
            fi
            mkdir $HADOOP_HOME/{data,logs,tmp,pids}
            $replace_line_func
            # JAVA_HOME
            for x in hadoop-env.sh yarn-env.sh mapred-env.sh
            do
                replace_line_func $HADOOP_HOME/etc/hadoop/\$x 'export JAVA_HOME=' 'export JAVA_HOME=$JAVA_HOME' 2
            done
            # NAMENODE JVMOPT
            replace_line_func $HADOOP_HOME/etc/hadoop/hadoop-env.sh 'HADOOP_NAMENODE_OPTS_NOT' 'HADOOP_NAMENODE_OPTS=\"$HDFS_NAMENODE_ODPS\"' 2

            # HADOOP_PID_DIR YARN_PID_DIR
            replace_line_func $HADOOP_HOME/etc/hadoop/hadoop-env.sh 'export HADOOP_PID_DIR=' 'export HADOOP_PID_DIR=$HADOOP_HOME/pids' 2
            replace_line_func $HADOOP_HOME/sbin/yarn-daemon.sh 'export YARN_PID_DIR=' 'export YARN_PID_DIR=$HADOOP_HOME/pids' 2
            # ulimit 
            replace_line_func $HADOOP_HOME/sbin/hadoop-daemon.sh 'ulimit -n' 'ulimit -SHn 65535' 2
            replace_line_func $HADOOP_HOME/sbin/yarn-daemon.sh 'ulimit -n' 'ulimit -SHn 65535' 2
            
            cd $HADOOP_HOME/etc/hadoop/
            # capacity-scheduler.xml
            sed -i 's/0.1/0.8/' capacity-scheduler.xml
            sed -i 's/resource.DefaultResourceCalculator/resource.DominantResourceCalculator/' capacity-scheduler.xml
            # slaves
            echo $HDFS_DATANODE | tr ',' '\n' | sort -u > slaves
            cd $HADOOP_HOME/sbin
            rm -rf *.cmd
            cd $HADOOP_HOME/bin
            rm -rf *.cmd
        " false
        if [ $? != 0 ];then 
            LOG_ERROR "$machine DEPLOY FAIL"
            exit -1
        else
            LOG "$machine DEPLOY SUCC"
        fi
        scp -q $SCRIPT_PATH/tmp_config/*.xml $machine:$HADOOP_HOME/etc/hadoop/
        scp -q $SCRIPT_PATH/tmp_config/hadoop.sh $machine:/etc/profile.d/hadoop.sh
    done
    rm -rf $SCRIPT_PATH/tmp_config
    LOG "==========END TO DEPLOY=========="
}

function hadoop_config() {
    tmp_dir=$SCRIPT_PATH/tmp_config
    rm -rf $tmp_dir
    mkdir $tmp_dir
    if [ "x$HADOOP_HA" == "xtrue" ];then  
        cp -a ./config/hadoop/cluster-ha/*.xml $tmp_dir
    else
        cp -a ./config/hadoop/cluster/*.xml $tmp_dir
    fi
    cd $tmp_dir/
    xml_files=`ls *.xml`
    need_rp_vars=$(grep -e 'HADOOP_' -e 'HDFS_' -e 'YARN_' -e 'USER' $SCRIPT_PATH/fast_install_config.sh |grep -v '#'|cut -d"=" -f1)
    HDFS_NAMENODE_HANDELER_COUNT=`n=$(echo $HDFS_DATANODE | tr ',' '\n' | wc -l);python -c "import math ; num=int(math.log($n) * 20); print(10 if num<10 else num)"`
    for var in $need_rp_vars HDFS_NAMENODE_HANDELER_COUNT
    do
        for xml_file in $xml_files
        do
            sed -i "s#{$var}#`eval echo '$'"$var"`#g"  $xml_file
            #echo sed -i "s#{$var}#`eval echo '$'"$var"`#g"  $xml_file
        done
    done
    echo "\
export HADOOP_HOME=$HADOOP_HOME
export PATH=\$PATH:\$HADOOP_HOME/bin:\$HADOOP_HOME/sbin
"  > hadoop.sh
}

function first_start_hadoop() {
    LOG "start cluster"
    if [ "x$HADOOP_HA" == "xtrue" ];then  
        # start JournalNode first
        ms=$(echo $HDFS_HA_JOURNALNODE | tr ';' '\n' | cut -d':' -f1)
        for machine in $ms
        do
            execute_and_check_order $machine "$HADOOP_HOME/sbin/hadoop-daemon.sh start journalnode" true
        done
        sleep 2s
        #format 
        execute_and_check_order $HDFS_NAMENODE "$HADOOP_HOME/bin/hdfs namenode -format" false
        execute_and_check_order $HDFS_NAMENODE "$HADOOP_HOME/bin/hdfs zkfc -formatZK" true
        
        execute_and_check_order $HDFS_NAMENODE "$HADOOP_HOME/sbin/hadoop-daemon.sh start namenode" true
        execute_and_check_order $HDFS_HA_NAMENODE_2 "$HADOOP_HOME/bin/hdfs namenode -bootstrapStandby" true
        execute_and_check_order $HDFS_HA_NAMENODE_2 "$HADOOP_HOME/sbin/hadoop-daemon.sh start namenode" true
        # start zkfc
        execute_and_check_order $HDFS_NAMENODE "$HADOOP_HOME/sbin/hadoop-daemon.sh start zkfc" true
        execute_and_check_order $HDFS_HA_NAMENODE_2 "$HADOOP_HOME/sbin/hadoop-daemon.sh start zkfc" true
        # start datanode
        execute_and_check_order $HDFS_NAMENODE "$HADOOP_HOME/sbin/start-dfs.sh" true
        
        #start yarn
        execute_and_check_order $YARN_RESOURCEMANAGER "$HADOOP_HOME/sbin/start-yarn.sh" true
        execute_and_check_order $YARN_HA_RESOURCEMANAGER_2 "$HADOOP_HOME/sbin/yarn-daemon.sh start resourcemanager" true
        
    else
        execute_and_check_order $HDFS_NAMENODE "$HADOOP_HOME/bin/hdfs namenode -format" true
        if [ $? == 0 ];then 
            execute_and_check_order $HDFS_NAMENODE "$HADOOP_HOME/sbin/start-dfs.sh" true
            execute_and_check_order $HDFS_NAMENODE "$HADOOP_HOME/sbin/start-yarn.sh" true
        fi
    fi
}

function start_hadoop() {
    LOG "start cluster"
    execute_and_check_order $HDFS_NAMENODE "$HADOOP_HOME/sbin/start-dfs.sh" true
    execute_and_check_order $HDFS_NAMENODE "$HADOOP_HOME/sbin/start-yarn.sh" true
    execute_and_check_order $YARN_HA_RESOURCEMANAGER_2 "$HADOOP_HOME/sbin/yarn-daemon.sh start resourcemanager" true
}


function is_pub() {
    pub_start=$(echo "$1" | head -n 1 |cut -d ' ' -f2)
    pub_start=${pub_start:0:4}
    if [ "x$pub_start" != "xAAAA" ]; then
        LOG_ERROR "get pub err"
        exit -1
    fi
}


function ssh_login_free_trust() {
    idpub1=`execute_and_check_order $HDFS_NAMENODE "
    if [ ! -f ~/.ssh/id_rsa.pub ];then 
        ssh-keygen -t rsa -P '' -f ~/.ssh/id_rsa &>/dev/null
    fi
    cat ~/.ssh/id_rsa.pub
    " false`
    is_pub "$idpub1"
    if [ "x$HADOOP_HA" == "xtrue" ];then
        ms=$(echo "$HDFS_NAMENODE,$HDFS_DATANODE,$HDFS_HA_NAMENODE_2" | tr ',' '\n' | sort -u)
    else 
        ms=$(echo "$HDFS_NAMENODE,$HDFS_DATANODE" | tr ',' '\n' | sort -u)
    fi
    for dn in $ms
    do
        execute_and_check_order $dn "
        ssh_pub_key='$idpub1'
        has_key=\$(grep -s \"\$ssh_pub_key\" ~/.ssh/authorized_keys | wc -l )
        if [ \$has_key -eq 0 ];then 
            echo \"\$ssh_pub_key\" >> ~/.ssh/authorized_keys
        fi
        " true
        execute_and_check_order $HDFS_NAMENODE "ssh -o PasswordAuthentication=no -o StrictHostKeyChecking=no $dn echo ok" true
    done
    if [ "x$HADOOP_HA" == "xtrue" ];then
        idpub2=`execute_and_check_order $HDFS_HA_NAMENODE_2 "
        if [ ! -f ~/.ssh/id_rsa.pub ];then 
            ssh-keygen -t rsa -P '' -f ~/.ssh/id_rsa &>/dev/null
        fi
        cat ~/.ssh/id_rsa.pub
        " false`
        is_pub "$idpub2"
        for dn in $ms
        do
            execute_and_check_order $dn "
                ssh_pub_key='$idpub2'
                has_key=\$(grep -s \"\$ssh_pub_key\" ~/.ssh/authorized_keys | wc -l )
                if [ \$has_key -eq 0 ];then 
                    echo \"\$ssh_pub_key\" >> ~/.ssh/authorized_keys
                fi
        " true
            execute_and_check_order $HDFS_HA_NAMENODE_2 "ssh -o PasswordAuthentication=no -o StrictHostKeyChecking=no $dn echo ok" true
        done
    fi
    LOG "SSH_TRUST OK"
}

function hive_config() {
    if [ "x$HIVE_HA" == "xtrue" ];then
        for m in `echo $HIVE_HA_METASTORE | tr ',' '\n' | sort -u`
        do
            HIVE_METASTORE_URIS="$HIVE_METASTORE_URIS,thrift://${METASTORE}:9083"
            HIVE_METASTORE_URIS=${HIVE_METASTORE_URIS:1}
        done
    else
        METASTORE=`echo $HIVE_NODE | cut -d ',' -f1`
        HIVE_METASTORE_URIS="thrift://${METASTORE}:9083"
    fi
    tmp_dir=$SCRIPT_PATH/tmp_config
    rm -rf $tmp_dir
    mkdir $tmp_dir
    cp -a ./config/hive/*.xml $tmp_dir
    cd $tmp_dir/
    xml_files=`ls *.xml`
    need_rp_vars=$(grep -e 'HIVE_' -e 'USER' $SCRIPT_PATH/fast_install_config.sh |grep -v '#'|cut -d"=" -f1)
    for var in $need_rp_vars HIVE_METASTORE_URIS
    do
        for xml_file in $xml_files
        do
            sed -i "s#{$var}#`eval echo '$'"$var"`#g"  $xml_file
        done
    done
    echo "\
export HIVE_HOME=$HIVE_HOME
export PATH=\$PATH:\$HIVE_HOME/bin
"  > hive.sh
}
function install_hive() {
    hive_config
    cd $SCRIPT_PATH
    hive_tgz=$(ls apache-hive-2.*-bin.tar.gz 2>/dev/null | head -1)
    if [ "x$hive_tgz" == "x" ];then 
        try_wget $hive_tgz_url
        hive_tgz=$(basename $hive_tgz_url)
    fi
    if [ ! -f $hive_tgz ];then 
        LOG_ERROR "hadoop install file not find"
        exit -1
    fi
    mysql_jar=$(ls mysql-connector-java-5.*.jar 2>/dev/null| head -1)
    if [ "x$mysql_jar" == "x" ];then 
        try_wget $mysql_jar_url
        mysql_jar=$(basename $mysql_jar_url)
    fi
    if [ ! -f $mysql_jar ];then 
        LOG_ERROR "mysql jar not find"
        exit -1
    fi
    if [ "x$HIVE_HA" == "xtrue" ];then
        ms=$(echo $HIVE_NODE,$HIVE_HA_METASTORE,$HIVE_HA_HIVESERVER2 | tr " " "\n" |tr "," "\n"| grep -v '^$' | sort -u)
        for m in `echo $HIVE_HA_METASTORE | tr ',' '\n' | sort -u`
        do
            HIVE_METASTORE_URIS="$HIVE_METASTORE_URIS,thrift://${METASTORE}:9083"
            HIVE_METASTORE_URIS=${HIVE_METASTORE_URIS:1}
        done
    else
        ms=$(echo $HIVE_NODE | tr " " "\n" |tr "," "\n"| grep -v '^$' | sort -u)
        METASTORE=`echo $HIVE_NODE | cut -d ',' -f1`
        HIVE_METASTORE_URIS="thrift://${METASTORE}:9083"
    fi
    LOG "==========START TO DEPLOY=========="
    for machine in $ms
    do
        LOG "$machine start.."
        cd $SCRIPT_PATH
        execute_and_check_order $machine "mkdir -p $INSTALL_PATH/"
        scp -q $hive_tgz $machine:$INSTALL_PATH/$hive_tgz
        scp -q $mysql_jar $machine:$INSTALL_PATH/$mysql_jar
        execute_and_check_order $machine "
            # clean env first
            rm -rf $HIVE_HOME
            base_path=\"`dirname $HIVE_HOME`\"
            mkdir -p \$base_path
            
            # unzip file
            cd $INSTALL_PATH
            tar --no-same-owner -zxf $hive_tgz -C \$base_path/
            if [ \$? != 0 ];then
              echo '$machine tar $hive_tgz failed'
              exit -1
            fi
            rm -rf $INSTALL_PATH/$hive_tgz
            
            # rename dir
            mv \$base_path/${hive_tgz%\.tar\.gz} $HIVE_HOME
            
            if [ ! -d \"$HIVE_HOME\" ];then 
                echo '$machine $HIVE_HOME not exit'
                exit -1
            fi
            mv $INSTALL_PATH/$mysql_jar $HIVE_HOME/lib/
            mkdir $HIVE_HOME/{tmp,log}
            $replace_line_func
            echo 'export JAVA_HOME=$JAVA_HOME
export HIVE_HOME=$HIVE_HOME
export HADOOP_HOME=$HADOOP_HOME' >> $HIVE_HOME/conf/hive-env.sh
            
            replace_line_func $HIVE_HOME/bin/hive-config.sh 'export HADOOP_HEAPSIZE=' 'export HADOOP_HEAPSIZE=\${HADOOP_HEAPSIZE:-2048}'
            mv $HIVE_HOME/conf/hive-log4j2.properties.template $HIVE_HOME/conf/hive-log4j2.properties
            replace_line_func $HIVE_HOME/conf/hive-log4j2.properties 'erty.hive.log.dir' 'property.hive.log.dir = $HIVE_HOME/log/'            
        " true
        if [ $? != 0 ];then 
            LOG_ERROR "$machine DEPLOY FAIL"
            exit -1
        else
            LOG "$machine DEPLOY SUCC"
        fi
        scp -q $SCRIPT_PATH/tmp_config/*.xml $machine:$HIVE_HOME/conf/
        scp -q $SCRIPT_PATH/tmp_config/hive.sh $machine:/etc/profile.d/hive.sh
    done
    init_mysql
    restart_hive
}

function restart_hive() {
start_metastore="
    pid=\$(jps -lm| grep org.apache.hadoop.hive.metastore.HiveMetaStore | cut -d ' ' -f 1)
    if [ \"x\$pid\" != \"x\" ];then 
        kill -9 \$pid
    fi
    cd $HIVE_HOME/bin
    nohup ./hive --service metastore >> ../log/metastore.out 2>&1 &
"
start_hiveserver2="
    pid=\$(jps -lm| grep org.apache.hive.service.server.HiveServer2 | cut -d ' ' -f 1)
    if [ \"x\$pid\" != \"x\" ];then 
        kill -9 \$pid
    fi
    cd $HIVE_HOME/bin
    nohup ./hive --service hiveserver2 >> ../log/hiveserver2.out 2>&1 &
"

    hive_first_machine=`echo $HIVE_NODE | cut -d ',' -f1`
    #启动
    if [ "x$HIVE_HA" == "xtrue" ];then
        for ms in `echo $HIVE_HA_METASTORE | tr ',' '\n' | sort -u`
        do
            execute_and_print_order $ms "$start_metastore" true
        done
        for ms in `echo $HIVE_HA_HIVESERVER2 | tr ',' '\n' | sort -u`
        do
            execute_and_print_order $ms "$start_hiveserver2" true
        done
    else 
        execute_and_print_order $hive_first_machine "$start_metastore"  true
        execute_and_print_order $hive_first_machine "$start_hiveserver2"  true
    fi

}

function init_mysql() {
    hive_first_machine=`echo $HIVE_NODE | cut -d ',' -f1`
    execute_and_check_order $hive_first_machine "mysql -h$HIVE_MYSQL_HOSTNAME \
-P$HIVE_MYSQL_PORT \
-u$HIVE_MYSQL_USERNAME \
-p$HIVE_MYSQL_PASSWORD \
-sNe \"drop database if exists $HIVE_MYSQL_DATABASE;create database $HIVE_MYSQL_DATABASE;select 'OK'\"
    " true
    execute_and_check_order $hive_first_machine "$HIVE_HOME/bin/schematool -dbType mysql -initSchema" true
    execute_and_check_order $hive_first_machine "mysql -h$HIVE_MYSQL_HOSTNAME \
-P$HIVE_MYSQL_PORT \
-u$HIVE_MYSQL_USERNAME \
-p$HIVE_MYSQL_PASSWORD \
-D$HIVE_MYSQL_DATABASE \
-sNe 'alter table COLUMNS_V2 modify column COMMENT varchar(256) character set utf8;\
alter table TABLE_PARAMS modify column PARAM_VALUE varchar(4000) character set utf8;\
alter table PARTITION_KEYS modify column PKEY_COMMENT varchar(4000) character set utf8;'
" true
}

function spark_config() {
    if [ "x$HADOOP_HA" != "xtrue" ];then
        HDFS_NAMESERVICE="$HDFS_NAMENODE:${HDFS_NAMENODE_RPC_PORT:=9000}"
    else
        HDFS_NAMESERVICE="$HDFS_HA_CLUSTER"
    fi
    tmp_dir=$SCRIPT_PATH/tmp_config
    rm -rf $tmp_dir
    mkdir $tmp_dir
    cp -a ./config/spark/hive-site-sub.xml $tmp_dir
    cd $tmp_dir/
    xml_files=`ls *.xml`
    for var in HDFS_NAMESERVICE
    do
        sed -i "s#{$var}#`eval echo '$'"$var"`#g"  hive-site-sub.xml
    done
    
}

function install_spark() {
    spark_config
    cd $SCRIPT_PATH
    LOG "==========START TO DEPLOY SPARK=========="
    LOG "==========UNZIP FILE=========="
    spark_tgz=$(ls spark-2.*-bin-without-hadoop.tgz | head -1)
    if [ "x$spark_tgz" == "x" ];then
        try_wget $spark_tgz_url
        spark_tgz=$(basename $spark_tgz_url)
    fi
    spark_dir=${spark_tgz%\.tgz}
    if [ ! -f $spark_tgz ];then 
        LOG_ERROR "hadoop install file not find"
        exit -1
    fi
    rm -rf $spark_dir
    tar --no-same-owner -zxf $spark_tgz
    rm -rf $spark_dir/jars/orc-*.jar
    rm -rf $spark_dir/jars/parquet-*.jar
    LOG "==========SEND JAR TO ALL DN=========="
    #ALL DATANODE ADD JAR, MODIFY yarn-site.xml
    if [ "x$HADOOP_HA" == "xtrue" ];then
        ms=$(echo "$HDFS_NAMENODE,$HDFS_DATANODE,$HDFS_HA_NAMENODE_2" | tr ',' '\n' | sort -u)
    else 
        ms=$(echo "$HDFS_NAMENODE,$HDFS_DATANODE" | tr ',' '\n' | sort -u)
    fi
    for machine in $ms
    do
        echo "datanode $ms scp jar"
        scp -q $spark_dir/yarn/spark-*-yarn-shuffle.jar $machine:$HADOOP_HOME/share/hadoop/yarn/lib/
        echo "datanode $ms modify yarn-site.xml"
        execute_and_check_order $machine "python -c '
$replace_config_func
replace_config_func(\"$HADOOP_HOME/etc/hadoop/yarn-site.xml\",\"<value>mapreduce_shuffle</value>\",\"<value>mapreduce_shuffle,spark_shuffle</value>\")
replace_config_func(\"$HADOOP_HOME/etc/hadoop/yarn-site.xml\",\"</configuration>\",\"\"\"
    <property>
    　　<name>yarn.nodemanager.aux-services.spark_shuffle.class</name>
    　　<value>org.apache.spark.network.yarn.YarnShuffleService</value>
    </property>
</configuration>
\"\"\")
'" true 

    done
    
    # ADD JAR TO HDFS
    LOG "=========ADD JAR TO HDFS=========="
    first_machine=`echo "$ms" | head -1 | cut -d' ' -f1`
    echo "choose $first_machine to init hdfs spark jar"
    execute_and_check_order $first_machine "
        rm -rf /tmp/spark-hdfs-jars
        mkdir -p /tmp/spark-hdfs-jars
        $HADOOP_HOME/bin/hadoop fs -rm -r -f /spark-jars
        $HADOOP_HOME/bin/hadoop fs -mkdir -p /spark-history
        $HADOOP_HOME/bin/hadoop fs -mkdir -p /spark-jars
    " true
    scp -q $spark_dir/jars/*.jar $first_machine:/tmp/spark-hdfs-jars
    execute_and_check_order $first_machine "
        cd /tmp/spark-hdfs-jars
        $HADOOP_HOME/bin/hadoop fs -put *.jar /spark-jars
        rm -rf /tmp/spark-hdfs-jars
        " true
    LOG "=========ADD JAR TO HIVE=========="
    if [ "x$HIVE_HA" == "xtrue" ];then
        ms=$(echo $HIVE_NODE,$HIVE_HA_METASTORE,$HIVE_HA_HIVESERVER2 | tr " " "\n" |tr "," "\n"| grep -v '^$' | sort -u)
    else
        ms=$(echo $HIVE_NODE | tr " " "\n" |tr "," "\n"| grep -v '^$' | sort -u)
    fi
    hive_site_sub_xml="`cat $SCRIPT_PATH/tmp_config/hive-site-sub.xml`"
    for machine in $ms
    do
        LOG "$machine start.."
        cd $SCRIPT_PATH
        execute_and_check_order $machine "mkdir -p $INSTALL_PATH/"
        execute_and_check_order $machine "
            cd $HIVE_HOME/lib/
            for rmjar in \$(ls spark-*.jar | grep -v spark-client)
            do
                rm -f \$rmjar
            done
            if [ -f $HIVE_HOME/conf/.spark_installed ];then 
                echo '$machine spark install all ready, exit'
                exit 0
            fi
            python -c '
$replace_config_func
replace_config_func(\"$HIVE_HOME/conf/hive-site.xml\",\"</configuration>\",\"\"\"
$hive_site_sub_xml
</configuration>
\"\"\")
'
            if [ \$? -eq 0 ];then 
                touch $HIVE_HOME/conf/.spark_installed
            else
                exit -1
            fi 
        " false
        if [ $? != 0 ];then 
            LOG_ERROR "$machine modify fail"
            exit -1
        else
            LOG "$machine modify succ"
        fi
        LOG "scp jar to hive: $machine .."
        scp -q $spark_dir/jars/spark-*.jar $machine:$HIVE_HOME/lib/
    done
    execute_and_check_order $HDFS_NAMENODE "$HADOOP_HOME/sbin/stop-yarn.sh; $HADOOP_HOME/sbin/start-yarn.sh" true
    restart_hive
}


if [ $# -eq 0 ]; then
  echo -e "ERROR: args err\n\t USEAGE: $EXAMPLE"
  exit -1
fi
source_config
case $1 in 
    "java")
        install_java ${@:2}
    ;;
    "hadoop")
        install_hadoop
        first_start_hadoop
    ;;
    "hive")
        install_hive
    ;;
    "spark")
        install_spark
    ;;
    *)
    echo -e "ERROR: args err\n\t USEAGE: $EXAMPLE"
    ;;
esac
 