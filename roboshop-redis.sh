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

is_redis_installed(){
	if [ $1 -eq 0 ];then
	   echo -e "$TIMESTAMP $Y Redis already installed... SKIPPING $N" | tee -a $LOGS_FILE
	else
	   echo "Installing Redis..."
	   dnf install redis -y &>> $LOGS_FILE
	   VALIDATE $? "Installing Redis"

	   sed -i -e 's/127.0.0.1/0.0.0.0/g' -e '/protected-mode/ c protected-mode no'  /etc/redis/redis.conf

    fi
}

dnf module disable redis -y &>> LOGS_FILE
VALIDATE $? "Disable Redis"
dnf module enable redis:7 -y &>> $LOGS_FILE
VALIDATE $? "Enabling Redis 7"

set +e
trap '' ERR

dnf list installed redis &>> $LOGS_FILE 
REDIS_STATUS=$?

set -e
trap 'echo -e "$R Error at line $LINENO $N" | tee -a $LOGS_FILE' ERR

is_redis_installed $REDIS_STATUS


systemctl enable redis &>> $LOGS_FILE
VALIDATE $? "Enabling Rdis"

systemctl start redis &>> $LOGS_FILE
VALIDATE $? "Starting redis"



STATUS=$(systemctl is-active redis)
 if [ "$STATUS" == "active" ]; then
    echo -e "$G Redis is running! $N" | tee -a $LOGS_FILE

 else
    echo -e "$R Redis is not running! $N" | tee -a $LOGS_FILE
    exit 1
fi




