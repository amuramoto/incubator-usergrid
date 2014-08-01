#!/bin/bash

# 
#  Licensed to the Apache Software Foundation (ASF) under one or more
#   contributor license agreements.  The ASF licenses this file to You
#  under the Apache License, Version 2.0 (the "License"); you may not
#  use this file except in compliance with the License.
#  You may obtain a copy of the License at
# 
#      http://www.apache.org/licenses/LICENSE-2.0
# 
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.  For additional information regarding
#  copyright in this work, please see the NOTICE file in the top level
#  directory of this distribution.
#

echo "${HOSTNAME}" > /etc/hostname
echo "127.0.0.1 ${HOSTNAME}" >> /etc/hosts
hostname `cat /etc/hostname`

echo "US/Eastern" > /etc/timezone
dpkg-reconfigure -f noninteractive tzdata

PKGS="openjdk-7-jdk tomcat7 s3cmd ntp unzip groovy"
apt-get update
apt-get -y --force-yes install ${PKGS}
/etc/init.d/tomcat7 stop

# Install AWS Java SDK and get it into the Groovy classpath
curl http://sdk-for-java.amazonwebservices.com/latest/aws-java-sdk.zip > /tmp/aws-sdk-java.zip
cd /usr/share/
unzip /tmp/aws-sdk-java.zip 
mkdir -p /home/ubuntu/.groovy/lib
cp /usr/share/aws-java-sdk-*/third-party/*/*.jar /home/ubuntu/.groovy/lib
cp /usr/share/aws-java-sdk-*/lib/* /home/ubuntu/.groovy/lib 
# except for evil stax
rm /home/ubuntu/.groovy/lib/stax*
ln -s /home/ubuntu/.groovy /root/.groovy

# Build environment for Groovy scripts
. /etc/profile.d/aws-credentials.sh
. /etc/profile.d/usergrid-env.sh

# Copy in our own server.xml to set Tomcat's thread pool size
cp /usr/share/usergrid/lib/server.xml /var/lib/tomcat7/conf
chown tomcat7 /var/lib/tomcat7/conf/server.xml 

# Set Tomcat RAM size and path to log4j.properties
export JAVA_OPTS="-Djava.awt.headless=true -Xmx1024m -Dlog4j.configuration=file:/usr/share/usergrid/lib/log4j.properties"
sed -i 's/Xmx128m/Xmx1024m -Dlog4j.configuration=file\:\/usr\/share\/usergrid\/lib\/log4j\.properties/' /etc/default/tomcat7

cd /usr/share/usergrid/init_instance
./install_oraclejdk.sh 

# Wait for enough Cassandra nodes then deploy and restart Tomcat 
cd /usr/share/usergrid/scripts
groovy wait_for_instances.groovy cassandra ${CASSANDRA_NUM_SERVERS}
groovy wait_for_instances.groovy graphite ${GRAPHITE_NUM_SERVERS}

mkdir -p /usr/share/tomcat7/lib 
groovy configure_usergrid.groovy > /usr/share/tomcat7/lib/usergrid-deployment.properties 

rm -rf /var/lib/tomcat7/webapps/*
cp -r /usr/share/usergrid/webapps/* /var/lib/tomcat7/webapps
groovy configure_portal_new.groovy >> /var/lib/tomcat7/webapps/portal/config.js

cd /usr/share/usergrid/init_instance
./install_yourkit.sh
./init_jmx_remote.sh

# Set Tomcat RAM (80% max) and threads (250/core)
case `(curl http://169.254.169.254/latest/meta-data/instance-type)` in 
'm1.small' )
	export TOMCAT_RAM=1250M
	export TOMCAT_THREADS=250
;; 
'm1.medium' ) 
	export TOMCAT_RAM=3G
	export TOMCAT_THREADS=500
;; 
'm1.large' ) 
	export TOMCAT_RAM=6G
	export TOMCAT_THREADS=1000
;; 
'm1.xlarge' ) 
	export TOMCAT_RAM=12G
	export TOMCAT_THREADS=2000
;; 
'm3.xlarge' ) 
	export TOMCAT_RAM=12G
	export TOMCAT_THREADS=3250
;; 
'm3.large' ) 
	export TOMCAT_RAM=6G
	export TOMCAT_THREADS=1600
;; 
'c3.4xlarge' ) 
	export TOMCAT_RAM=24G
	export TOMCAT_THREADS=4000
esac 

sudo sed -i.bak "s/Xmx128m/Xmx${TOMCAT_RAM} -Xms${TOMCAT_RAM}/g" /etc/default/tomcat7
sudo sed -i.bak "s/<Connector/<Connector maxThreads=\"${TOMCAT_THREADS}\" acceptCount=\"${TOMCAT_THREADS}\" maxConnections=\"${TOMCAT_THREADS}\"/g" /var/lib/tomcat7/conf/server.xml 

# Go
/etc/init.d/tomcat7 start

# tag last so we can see in the console that the script ran to completion
cd /usr/share/usergrid/scripts
groovy tag_instance.groovy
