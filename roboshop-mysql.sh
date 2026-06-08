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

is_mysql_installed(){
	if [ $1 -eq 0 ];then
	   echo -e "$TIMESTAMP $Y MYSQL already installed... SKIPPING $N" | tee -a $LOGS_FILE
	else
	   echo "Installing MYSQL..."
	   dnf install mysql-server -y &>> $LOGS_FILE
	   VALIDATE $? "Installing Mysql" 
    fi
}


set +e
trap '' ERR

dnf list installed mysql-server &>> $LOGS_FILE 
MYSQL_STATUS=$?

set -e
trap 'echo -e "$R Error at line $LINENO $N" | tee -a $LOGS_FILE' ERR

is_mysql_installed $MYSQL_STATUS


systemctl enable mysqld &>> $LOGS_FILE
VALIDATE $? "Enabling MYSQL"

systemctl start mysqld &>> $LOGS_FILE
VALIDATE $? "Starting MYSQL"

mysql_secure_installation --set-root-pass RoboShop@1
VALIDATE $? "Setting Root password"

STATUS=$(systemctl is-active mysqld)
 if [ "$STATUS" == "active" ]; then
    echo -e "$G MYSQL is running! $N" | tee -a $LOGS_FILE

 else
    echo -e "$R MySQl is not running! $N" | tee -a $LOGS_FILE
    exit 1
fi




