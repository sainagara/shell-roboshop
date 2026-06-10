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

is_python_installed(){
    if [ $1 -eq 0 ]; then
        echo -e "$TIMESTAMP $Y Python Packages are already installed... SKIPPING $N" | tee -a $LOGS_FILE
    else
        echo -e "$Y Installing Python... $N" | tee -a $LOGS_FILE
        dnf install python3 -y &>> $LOGS_FILE
        VALIDATE $? "Python Packages Installation"
    fi
}


echo -e "$Y Installing Python dependencies... $N" | tee -a $LOGS_FILE
dnf install gcc python3-devel -y &>> $LOGS_FILE
VALIDATE $? "Python Build Dependencies"

# ── Python Setup ──────────────────────────────────────────────

disable_error_handling
dnf list installed python3 &>> $LOGS_FILE
PYTHON_STATUS=$?
enable_error_handling

is_python_installed $PYTHON_STATUS

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

rm -rf /tmp/payment.zip
VALIDATE $? "Remove Payment Zip"     

mkdir -p /app

# ── Download Application ──────────────────────────────────────           

curl -o /tmp/payment.zip \
    https://roboshop-artifacts.s3.amazonaws.com/payment-v3.zip \
    &>> $LOGS_FILE
VALIDATE $? "Downloading Payment"

cd /app
unzip /tmp/payment.zip &>> $LOGS_FILE
VALIDATE $? "Extracting Payment Service Code"

pip3 install -r requirements.txt &>> $LOGS_FILE
VALIDATE $? "Installing Dependencies"


# ── Copy Service File ─────────────────────────────────────────
cp $SCRIPT_DIR/payment.service \
    /etc/systemd/system/payment.service
VALIDATE $? "Copying Payment Service File"

# ── Start Service ─────────────────────────────────────────────
systemctl daemon-reload &>> $LOGS_FILE
VALIDATE $? "Daemon Reload"                       

systemctl enable payment &>> $LOGS_FILE
VALIDATE $? "Enabling payment Service"

systemctl start payment &>> $LOGS_FILE
VALIDATE $? "Starting Payment Service"

# ── Verify ────────────────────────────────────────────────────
STATUS=$(systemctl is-active payment)
if [ "$STATUS" == "active" ]; then
    echo -e "$G Payment Service is running! $N" | tee -a $LOGS_FILE
else
    echo -e "$R Payment service is not running! $N" | tee -a $LOGS_FILE
    exit 1
fi

        