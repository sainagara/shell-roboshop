#!/bin/bash

set -euo pipefail

LOGS_DIR="/var/log/roboshop"
LOGS_FILE="$LOGS_DIR/$0.log"
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
SCRIPT_DIR=$(pwd)
MYSQL_HOST="roboshop.mysql.aslearnings.online"

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

is_maven_installed(){
    if [ $1 -eq 0 ]; then
        echo -e "$TIMESTAMP $Y Maven already installed... SKIPPING $N" | tee -a $LOGS_FILE
    else
        echo -e "$Y Installing Maven... $N" | tee -a $LOGS_FILE
        dnf install maven -y &>> $LOGS_FILE
        VALIDATE $? "Maven Installation"
    fi
}

is_mysql_installed(){
    if [ $1 -eq 0 ]; then
        echo -e "$TIMESTAMP $Y Mysql already installed... SKIPPING $N" | tee -a $LOGS_FILE
    else
        echo -e "$Y Installing Mysql Client... $N" | tee -a $LOGS_FILE
        dnf install mysql -y &>> $LOGS_FILE
        VALIDATE $? "MySql Installation"
    fi
}

# ── Maven and java Setup ──────────────────────────────────────────────
disable_error_handling
dnf list installed maven &>> $LOGS_FILE
MAVEN_STATUS=$?
enable_error_handling

is_maven_installed $MAVEN_STATUS

# ── MYSql client setup BEFORE app ────────────────────
disable_error_handling
dnf list installed mysql &>> $LOGS_FILE
MYSQL_STATUS=$?
enable_error_handling

is_mysql_installed $MYSQL_STATUS

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
rm -rf /tmp/shipping.zip
VALIDATE $? "Remove Shipping Zip"                

curl -o /tmp/shipping.zip \
    https://roboshop-artifacts.s3.amazonaws.com/shipping-v3.zip \
    &>> $LOGS_FILE
VALIDATE $? "Downloading Shipping Service"

cd /app
unzip /tmp/shipping.zip &>> $LOGS_FILE
VALIDATE $? "Extracting Shipping SErvice Code"

mvn clean package &>> $LOGS_FILE
VALIDATE $? "Installing Mavne Dependencies"

mv target/shipping-1.0.jar shipping.jar
VALIDATE $? "Copying jar file from target folder to app folder"

# ── Load MYsql Schema ───────────────────────────────────────
disable_error_handling
mysql -h $MYSQL_HOST \
      -u root \
      -pRoboShop@1 \
      -e "use cities" &>> $LOGS_FILE
DB_STATUS=$?                        # Fix 1
enable_error_handling

if [ $DB_STATUS -ne 0 ]; then
    mysql -h $MYSQL_HOST -uroot -pRoboShop@1 < /app/db/schema.sql
    mysql -h $MYSQL_HOST -uroot -pRoboShop@1 < /app/db/app-user.sql
    mysql -h $MYSQL_HOST -uroot -pRoboShop@1 < /app/db/master-data.sql
    VALIDATE $? "Data loaded"
else
    echo -e "Data already loaded ... $Y SKIPPING $N"
fi

# ── Copy Service File ─────────────────────────────────────────
cp $SCRIPT_DIR/shipping.service \
    /etc/systemd/system/shipping.service
VALIDATE $? "Copying Shipping Service File"

# ── Start Service ─────────────────────────────────────────────
systemctl daemon-reload &>> $LOGS_FILE
VALIDATE $? "Daemon Reload"                       

systemctl enable shipping &>> $LOGS_FILE
VALIDATE $? "Enabling Shipping Service"

systemctl start shipping &>> $LOGS_FILE
VALIDATE $? "Starting Shipping Service"

# ── Verify ────────────────────────────────────────────────────
STATUS=$(systemctl is-active shipping)
if [ "$STATUS" == "active" ]; then
    echo -e "$G Shipping Service is running! $N" | tee -a $LOGS_FILE
else
    echo -e "$R Shipping Service is not running! $N" | tee -a $LOGS_FILE
    exit 1
fi

# ── Restart after schema load ─────────────────────────────────
systemctl restart shipping &>> $LOGS_FILE
VALIDATE $? "Restarting Shipping Service"        