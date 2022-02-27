# bigdata_shells

### fash_install.sh

A fast way for sql-boy to install hadoop cluster. 

Supports single node and distributed cluster installations. Also supports high availability.

#### Require:

- CentOS 7
- At least 4g memory, preferably 8g or larger
- Mysql 5.7
- JDK8
- Zookeeper (optional)

#### Installation steps:

##### 1.ssh trust

Establish ssh trust of the manage node to all nodes, for excample:

```shell
ssh-kegen
ssh-copy-id localhost
```

##### 2.modify `fast_install_config.sh` as you need.

Modify mysql account password and other information.

If you want to install all components on a single machine, you only need to modify the mysql information. 

If you want to install a highly available cluster, you need to provide the zookeeper connection information

##### 3.download file(optional)

Download the following files, you can choose the latest minor version under the same major version. and then put them in the same directory where the fast_install.sh script is located. If you don't want to download newer minor version manually, this scrips will download them automatically(Internet connection required).

- [hadoop-2.10.1.tar.gz](https://archive.apache.org/dist/hadoop/common/hadoop-2.10.1/hadoop-2.10.1.tar.gz)

- [apache-hive-2.3.9-bin.tar.gz](https://archive.apache.org/dist/hive/hive-2.3.9/apache-hive-2.3.9-bin.tar.gz)
- [spark-2.4.8-bin-without-hadoop.tgz](https://archive.apache.org/dist/spark/spark-2.4.8/spark-2.4.8-bin-without-hadoop.tgz)
- [mysql-connector-java-5.1.49.jar](https://repo1.maven.org/maven2/mysql/mysql-connector-java/5.1.49/mysql-connector-java-5.1.49.jar)

##### 4.run script

Put the above files in the same directory where the fast_install.sh script is located. then run

```shell
sh fast_install.sh hadoop
sh fast_install.sh hive
sh fast_install.sh spark
```

Check whether the installation is successful at each step.

##### 5.check service

hdfs: http://your-ip:50070/

yarn: http://your-ip:8088/

hiveserver2: your-ip:10000