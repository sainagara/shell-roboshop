#!/bin/bash

set -euo pipefail

LOGS_DIR="/var/log/roboshop"
LOGS_FILE="$LOGS_DIR/$0.log"
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

R="\e[31m"
G="\e[32m"
Y="\e[33m"
N="\e[0m"

mkdir -p $LOGS_DIR
touch $LOGS_FILE

trap 'echo -e "$R Error at line $LINENO $N" | tee -a $LOGS_FILE' ERR

USER_ID=$(id -u)

if [ $USER_ID -ne 0 ]; then
  echo -e "$TIMESTAMP [ERROR] $R Please run this script with root access $N" | tee -a $LOGS_FILE
    exit 1
fi

VALIDATE(){
	if [ $1 -ne 0 ]; then
	  echo -e " $TIMESTAMP [ERROR] $2.....$R Failure $N" | tee -a $LOGS_FILE
	  exit 1
	else
	 echo -e "$TIMESTAMP [INFO] $2....$G Succes $N" | tee -a $LOGS_FILE
	fi
}

is_mongodb_installed(){
	if [ $1 -eq 0 ];then
	   echo -e "$TIMESTAMP $Y MongoDB already installed... SKIPPING $N" | tee -a $LOGS_FILE
	else
	   echo "Installing Mongodb..."
	   dnf install mongodb-org -y &>> $LOGS_FILE
	   VALIDATE $? "Installing Mongodb"

	   sed -i 's/127.0.0.1/0.0.0.0/g' /etc/mongod.conf
       VALIDATE $? "Mongodb REmote Access" 
    fi
}

cp mongodb.repo /etc/yum.repos.d/mongodb.repo
VALIDATE $? "Copyng monododb.repo"

set +e
trap '' ERR

dnf list installed mongodb-org &>> $LOGS_FILE 
MONGODB_STATUS=$?

set -e
trap 'echo -e "$R Error at line $LINENO $N" | tee -a $LOGS_FILE' ERR

is_mongodb_installed $MONGODB_STATUS


systemctl enable mongod &>> $LOGS_FILE
VALIDATE $? "Enabling Mongodb"

systemctl start mongod &>> $LOGS_FILE
VALIDATE $? "Starting Mongodb"



STATUS=$(systemctl is-active mongod)
 if [ "$STATUS" == "active" ]; then
    echo -e "$G MongoDB is running! $N" | tee -a $LOGS_FILE

 else
    echo -e "$R MongoDB is not running! $N" | tee -a $LOGS_FILE
    exit 1
fi




