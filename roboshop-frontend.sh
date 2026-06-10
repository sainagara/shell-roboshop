#!/bin/bash

set -euo pipefail

LOGS_DIR="/var/log/roboshop"
LOGS_FILE="$LOGS_DIR/$0.log"
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
SCRIPT_DIR=$(pwd)

R="\e[31m"
G="\e[32m"
Y="\e[33m"
N="\e[0m"

mkdir -p $LOGS_DIR
touch $LOGS_FILE

trap 'echo -e "$R Error at line $LINENO $N" | tee -a $LOGS_FILE' ERR

USER_ID=$(id -u)
if [ $USER_ID -ne 0 ]; then
    echo -e "$TIMESTAMP [ERROR] $R Please run with root access $N" | tee -a $LOGS_FILE
    exit 1
fi

VALIDATE(){
    if [ $1 -ne 0 ]; then
        echo -e "$TIMESTAMP [ERROR] $2.....$R Failure $N" | tee -a $LOGS_FILE
        exit 1
    else
        echo -e "$TIMESTAMP [INFO] $2....$G Success $N" | tee -a $LOGS_FILE  
    fi
}

disable_error_handling(){
    set +e
    trap '' ERR
}

enable_error_handling(){
    set -e
    trap 'echo -e "$R Error at line $LINENO $N" | tee -a $LOGS_FILE' ERR
}

is_nginx_installed(){
    if [ $1 -eq 0 ]; then
        echo -e "$TIMESTAMP $Y NGINX is already installed... SKIPPING $N" | tee -a $LOGS_FILE
    else
        echo -e "$Y Installing Nginx... $N" | tee -a $LOGS_FILE
        dnf install nginx -y &>> $LOGS_FILE
        VALIDATE $? "Nginx Installation"
    fi
}


dnf module disable nginx -y &>> $LOGS_FILE
dnf module enable nginx:1.24 -y &>> $LOGS_FILE

disable_error_handling
dnf list installed nginx &>> $LOGS_FILE
NGINX_STATUS=$?
enable_error_handling

is_nginx_installed $NGINX_STATUS



rm -rf /usr/share/nginx/html/*  &>> $LOGS_FILE
VALIDATE $? "Removing Default Code"




rm -rf /tmp/frontend.zip
VALIDATE $? "Remove frontend Zip"                

curl -o /tmp/frontend.zip \
    https://roboshop-artifacts.s3.amazonaws.com/frontend-v3.zip \
    &>> $LOGS_FILE
VALIDATE $? "Downloading Frontend"

cd /usr/share/nginx/html/
unzip /tmp/frontend.zip &>> $LOGS_FILE
VALIDATE $? "Extracting frontend  Code"

rm -rf /etc/nginx/nginx.conf
VALIDATE $? "Removed Default conf"

cp $SCRIPT_DIR/nginx.conf  /etc/nginx/nginx.conf
VALIDATE $? "Copying Nginx Service File"


systemctl daemon-reload &>> $LOGS_FILE
VALIDATE $? "Daemon Reload"                       

systemctl enable nginx &>> $LOGS_FILE
VALIDATE $? "Enabling nginx Service"


systemctl restart nginx &>> $LOGS_FILE            
VALIDATE $? "Starting Nginx Service"

# ── Verify ────────────────────────────────────────────────────
STATUS=$(systemctl is-active nginx)
if [ "$STATUS" == "active" ]; then
    echo -e "$G nginx is running! $N" | tee -a $LOGS_FILE
else
    echo -e "$R nginx is not running! $N" | tee -a $LOGS_FILE
    exit 1
fi

        