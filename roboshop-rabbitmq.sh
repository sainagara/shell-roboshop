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

start_rabbitmq(){
    systemctl enable rabbitmq-server &>> $LOGS_FILE
    VALIDATE $? "Enabling RabbitMQ"

    systemctl start rabbitmq-server &>> $LOGS_FILE
    VALIDATE $? "Starting RabbitMQ"
}

is_rabbitmq_installed(){
	if [ $1 -eq 0 ];then
	   echo -e "$TIMESTAMP $Y RabbitMq already installed... SKIPPING $N" | tee -a $LOGS_FILE
	else
	   echo "Installing RabbitMq..."
	   dnf install rabbitmq-server -y &>> $LOGS_FILE
	   VALIDATE $? "Installing RabbitMq"
        
	   start_rabbitmq	

       rabbitmqctl add_user roboshop roboshop123 &>> $LOGS_FILE
       VALIDATE $? "Setting up User name and  password"

	   rabbitmqctl set_permissions -p / roboshop ".*" ".*" ".*" &>> $LOGS_FILE
       VALIDATE $? "setting permissions"
	   
    fi
}



cp rabbitmq.repo /etc/yum.repos.d/rabbitmq.repo
VALIDATE $? "Copyng rabbitmq.repo"

set +e
trap '' ERR

dnf list installed rabbitmq-server &>> $LOGS_FILE 
RABBITMQ_STATUS=$?

set -e
trap 'echo -e "$R Error at line $LINENO $N" | tee -a $LOGS_FILE' ERR

is_rabbitmq_installed $RABBITMQ_STATUS


start_rabbitmq



STATUS=$(systemctl is-active rabbitmq-server)
 if [ "$STATUS" == "active" ]; then
    echo -e "$G RabbitMq is running! $N" | tee -a $LOGS_FILE

 else
    echo -e "$R RabbitMq is not running! $N" | tee -a $LOGS_FILE
    exit 1
fi




