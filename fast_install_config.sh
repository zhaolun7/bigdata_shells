INSTALL_PATH=/opt/data
JAVA_HOME=/home/rcp/java

USER=`whoami`
USER_HOME=`cd ~;pwd`
#===================HADOOP====================

HADOOP_HOME=$INSTALL_PATH/hadoop
HDFS_REPLICATION=1
HDFS_NAMENODE=CS-101
HDFS_DATANODE=CS-101,CS-102,CS-103
HDFS_DATANODE_DATA_DIR=/data1/hadoop_data,/data2/hadoop_data

HDFS_NAMENODE_ODPS="-Xmx1024m -Xms1024m"
HDFS_NAMENODE_HANDELER_COUNT=`n=$(echo $HDFS_DATANODE | tr ',' '\n' | wc -l);python -c "import math ; print int(math.log($n) * 20)"`

YARN_RESOURCEMANAGER=$HDFS_NAMENODE
YARN_NODEMANAGER=$HDFS_DATANODE
YARN_NODEMANAGER_CPU_VCORES=4
YARN_NODEMANAGER_MEM_MB=4096

# HADOOP HA include HDFS and YARN
HADOOP_HA=false 
# HDFS HA
HDFS_HA_CLUSTER=mycluster
HDFS_HA_NAMENODE_2=CS-102
HDFS_HA_ZK_ROOT=CS-101:2181
HDFS_HA_JOURNALNODE="CS-101:8485;CS-102:8485;CS-103:8485"
# YARN HA
YARN_HA_CLUSTER=$HDFS_HA_CLUSTER
YARN_HA_RESOURCEMANAGER_2=$HDFS_HA_NAMENODE_2
YARN_HA_ZK_ROOT=$HDFS_HA_ZK_ROOT

# TODO
#===================ZOOKEEPER==========================
ZOOKEEPER_HOME=$INSTALL_PATH/zookeeper
ZOOKEEPER_NODE=CS-101
ZOOKEEPER_PORT=2181
#====================MYSQL===========================

#====================HIVE==============================
HIVE_HOME=$INSTALL_PATH/hive
HIVE_NODE=CS-101
#====================SPARK=============================
SPARK_HOME=$INSTALL_PATH/spark