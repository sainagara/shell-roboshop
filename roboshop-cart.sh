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

is_nodejs_installed(){
    if [ $1 -eq 0 ]; then
        echo -e "$TIMESTAMP $Y NodeJS already installed... SKIPPING $N" | tee -a $LOGS_FILE
    else
        echo -e "$Y Installing NodeJS... $N" | tee -a $LOGS_FILE
        dnf install nodejs -y &>> $LOGS_FILE
        VALIDATE $? "NodeJS Installation"
    fi
}



# ── NodeJS Setup ──────────────────────────────────────────────
dnf module disable nodejs -y &>> $LOGS_FILE
dnf module enable nodejs:20 -y &>> $LOGS_FILE

disable_error_handling
dnf list installed nodejs &>> $LOGS_FILE
NODEJS_STATUS=$?
enable_error_handling

is_nodejs_installed $NODEJS_STATUS

# ── Create User ───────────────────────────────────────────────

disable_error_handling
id roboshop &>> $LOGS_FILE
USER_STATUS=$?
enable_error_handling

if [ $USER_STATUS -ne 0 ]; then
    useradd --system \
            --home /app \
            --shell /sbin/nologin \
            --comment "roboshop system user" \
            roboshop &>> $LOGS_FILE
    VALIDATE $? "System User Creation"
else
    echo -e "$TIMESTAMP $Y System User Already Created... SKIPPING $N" | tee -a $LOGS_FILE    
fi

rm -rf /app
VALIDATE $? "Removing Existing Code"

mkdir -p /app

# ── Download Application ──────────────────────────────────────
rm -rf /tmp/cart.zip
VALIDATE $? "Remove Cart  Zip"                

curl -o /tmp/cart.zip \
    https://roboshop-artifacts.s3.amazonaws.com/cart-v3.zip \
    &>> $LOGS_FILE
VALIDATE $? "Downloading Cart Service"

cd /app
unzip /tmp/cart.zip &>> $LOGS_FILE
VALIDATE $? "Extracting Cart Service Code"

npm install &>> $LOGS_FILE
VALIDATE $? "Installing Dependencies"


# ── Copy Service File ─────────────────────────────────────────
cp $SCRIPT_DIR/cart.service \
    /etc/systemd/system/cart.service
VALIDATE $? "Copying Cart Service File"

# ── Start Service ─────────────────────────────────────────────
systemctl daemon-reload &>> $LOGS_FILE
VALIDATE $? "Daemon Reload"                       

systemctl enable cart &>> $LOGS_FILE
VALIDATE $? "Enabling Cart Service"

systemctl start cart &>> $LOGS_FILE
VALIDATE $? "Starting Cart Service"

# ── Verify ────────────────────────────────────────────────────
STATUS=$(systemctl is-active cart)
if [ "$STATUS" == "active" ]; then
    echo -e "$G Cart Service is  running! $N" | tee -a $LOGS_FILE
else
    echo -e "$R Cart Service is not running! $N" | tee -a $LOGS_FILE
    exit 1
fi

        