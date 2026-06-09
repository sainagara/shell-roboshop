#!/bin/bash

set -euo pipefail

LOGS_DIR="/var/log/roboshop"
LOGS_FILE="$LOGS_DIR/$0.log"
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
SCRIPT_DIR=$(pwd)
MONGO_HOST="roboshop.mongodb.aslearnings.online"

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
        echo -e "$TIMESTAMP [INFO] $2....$G Success $N" | tee -a $LOGS_FILE  # Fix 4
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

is_mongosh_installed(){
    if [ $1 -eq 0 ]; then
        echo -e "$TIMESTAMP $Y Mongosh already installed... SKIPPING $N" | tee -a $LOGS_FILE
    else
        echo -e "$Y Installing mongosh... $N" | tee -a $LOGS_FILE
        dnf install mongodb-mongosh -y &>> $LOGS_FILE
        VALIDATE $? "Mongosh Installation"
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

# ── MongoDB client setup BEFORE app ────────────────────
cp $SCRIPT_DIR/mongodb.repo /etc/yum.repos.d/mongo.repo
VALIDATE $? "Copying MongoDB Repo"

disable_error_handling
dnf list installed mongodb-mongosh &>> $LOGS_FILE
MONGOSH_STATUS=$?
enable_error_handling

is_mongosh_installed $MONGOSH_STATUS

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
rm -rf /tmp/catalogue.zip
VALIDATE $? "Remove Catalogue Zip"                

curl -o /tmp/catalogue.zip \
    https://roboshop-artifacts.s3.amazonaws.com/catalogue-v3.zip \
    &>> $LOGS_FILE
VALIDATE $? "Downloading Catalogue"

cd /app
unzip /tmp/catalogue.zip &>> $LOGS_FILE
VALIDATE $? "Extracting Catalogue Code"

npm install &>> $LOGS_FILE
VALIDATE $? "Installing Dependencies"

# ── Load MongoDB Schema ───────────────────────────────────────
disable_error_handling
INDEX=$(mongosh --host $MONGO_HOST \
    --eval 'db.getMongo().getDBNames().indexOf("catalogue")')
enable_error_handling

if [ $INDEX -lt 0 ]; then
    echo -e "$Y Loading MongoDB schema... $N" | tee -a $LOGS_FILE
    mongosh --host $MONGO_HOST \
        /app/db/master-data.js &>> $LOGS_FILE     
    VALIDATE $? "Loading MongoDB Schema"
else
    echo -e "$Y Products already loaded... SKIPPING $N" | tee -a $LOGS_FILE  # Fix 7
fi

# ── Copy Service File ─────────────────────────────────────────
cp $SCRIPT_DIR/catalogue.service \
    /etc/systemd/system/catalogue.service
VALIDATE $? "Copying Service File"

# ── Start Service ─────────────────────────────────────────────
systemctl daemon-reload &>> $LOGS_FILE
VALIDATE $? "Daemon Reload"                       

systemctl enable catalogue &>> $LOGS_FILE
VALIDATE $? "Enabling Catalogue"

systemctl start catalogue &>> $LOGS_FILE
VALIDATE $? "Starting Catalogue"

# ── Verify ────────────────────────────────────────────────────
STATUS=$(systemctl is-active catalogue)
if [ "$STATUS" == "active" ]; then
    echo -e "$G Catalogue is running! $N" | tee -a $LOGS_FILE
else
    echo -e "$R Catalogue is not running! $N" | tee -a $LOGS_FILE
    exit 1
fi

# ── Restart after schema load ─────────────────────────────────
systemctl restart catalogue &>> $LOGS_FILE
VALIDATE $? "Restarting Catalogue Service"        