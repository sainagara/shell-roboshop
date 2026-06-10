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

is_golang_installed(){
    if [ $1 -eq 0 ]; then
        echo -e "$TIMESTAMP $Y Golang are already installed... SKIPPING $N" | tee -a $LOGS_FILE
    else
        echo -e "$Y Installing Golang... $N" | tee -a $LOGS_FILE
        dnf install golang -y &>> $LOGS_FILE
        VALIDATE $? "Golang Packages Installation"
    fi
}



# ── Python Setup ──────────────────────────────────────────────

disable_error_handling
dnf list installed golang &>> $LOGS_FILE
GOLANG_STATUS=$?
enable_error_handling

is_golang_installed $GOLANG_STATUS

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

rm -rf /tmp/dispatch.zip
VALIDATE $? "Remove Dispatch Zip"     

mkdir -p /app

# ── Download Application ──────────────────────────────────────           

curl -o /tmp/dispatch.zip \
    https://roboshop-artifacts.s3.amazonaws.com/dispatch-v3.zip \
    &>> $LOGS_FILE
VALIDATE $? "Downloading Dispatch"

cd /app
unzip /tmp/dispatch.zip &>> $LOGS_FILE
VALIDATE $? "Extracting Dispatch Service Code"

go mod init dispatch &>> $LOGS_FILE
go get &>> $LOGS_FILE
go build &>> $LOGS_FILE
VALIDATE $? "Installing Golang Dependencies"


# ── Copy Service File ─────────────────────────────────────────
cp $SCRIPT_DIR/dispatch.service \
    /etc/systemd/system/dispatch.service
VALIDATE $? "Copying Dispatch Service File"

# ── Start Service ─────────────────────────────────────────────
systemctl daemon-reload &>> $LOGS_FILE
VALIDATE $? "Daemon Reload"                       

systemctl enable dispatch &>> $LOGS_FILE
VALIDATE $? "Enabling Dispatch Service"

systemctl start dispatch &>> $LOGS_FILE
VALIDATE $? "Starting Dispatch Service"

# ── Verify ────────────────────────────────────────────────────
STATUS=$(systemctl is-active dispatch)
if [ "$STATUS" == "active" ]; then
    echo -e "$G Dispatch Service is running! $N" | tee -a $LOGS_FILE
else
    echo -e "$R Dispatch service is not running! $N" | tee -a $LOGS_FILE
    exit 1
fi

        