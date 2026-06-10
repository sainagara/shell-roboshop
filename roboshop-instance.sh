#!/bin/bash

set -euo pipefail

AMI="ami-0220d79f3f480ecf5"
HOSTED_ZONE="Z09423303UD7JE5COLBZI"
DOMAIN="aslearnings.online"

R="\e[31m"
G="\e[32m"
Y="\e[33m"
N="\e[0m"


trap 'echo "Error at line $LINENO, command: $BASH_COMMAND"' ERR

#validate the number of arguments paasing 

if [ $# -lt 2 ];then
    echo -e " $R [ERROR] At least 2 arguments required $N"
	echo -e " $Y [USAGE] sh $0 <create/delete> [instance1] [instance2] ... $N"
	exit 1
fi

ACTION=$1
shift

if [ "$ACTION" != "create" ] && [ "$ACTION" != "delete" ];then
  echo -e " $R [ERROR] first argument should be either create or delete $N" 
  echo -e " $Y [USAGE] sh $0 <create/delete> [instance1] [instance2] ... $N"
  exit 1
fi


get_instance_id(){
	aws ec2 describe-instances \
	  --filters "Name=tag:Name,Values=roboshop-$1" \
	            "Name=instance-state-name,Values=running" \
	  --query 'Reservations[0].Instances[0].InstanceId' \
	  --output text
}

create_instance(){
	aws ec2 run-instances \
	  --image-id $AMI \
	  --instance-type t3.micro \
	  --security-groups "common" "roboshop-$1" \
	  --count 1 \
	  --tag-specifications \
	     "ResourceType=instance,Tags=[{Key=Name,Value=roboshop-$1}]" \
	  --query 'Instances[0].InstanceId' \
	  --output text	 

}

get_public_ip(){
	aws ec2 describe-instances \
	 --instance-ids $1 \
	 --query 'Reservations[0].Instances[0].PublicIpAddress' \
	 --output text
}

get_private_ip(){
	aws ec2 describe-instances \
	  --instance-ids $1 \
	  --query 'Reservations[0].Instances[0].PrivateIpAddress' \
	  --output text
}

update_route53_records(){

	aws route53 change-resource-record-sets \
    --hosted-zone-id "Z09423303UD7JE5COLBZI" \
    --change-batch '{
        "Changes": [{
            "Action": "UPSERT",
            "ResourceRecordSet": {
                "Name": "'"$2"'",
                "Type": "A",
                "TTL": 1,
                "ResourceRecords": [{
                    "Value": "'"$1"'"
                }]
            }
        }]
    }'

}

delete_instance(){
	aws ec2 terminate-instances \
	--instance-ids $1

	if [ $? -ne 0 ]; then
      echo "Terminated Command Failed"
	  exit 1
    fi
	

}

get_instance_state(){
	aws ec2 describe-instances \
    --instance-ids $1 \
    --query 'Reservations[0].Instances[0].State.Name' \
    --output text

}

for instance in $@
do
  instance_id=$(get_instance_id $instance)

    if [ "$ACTION" == "create" ]; then
	    if [ "$instance_id" == "None" ];then
		  instance_id=$(create_instance $instance)
		  echo "Launched Instance: $instance_id"
		  aws ec2 wait instance-running \
		    --instance-ids $instance_id
		  echo "Instance is Running with id; $instance_id"

		else
		   echo " "$instance" alredy exist and running with id : $instance_id "
		fi

        if [ "robosho-$instance" == "roboshop-frontend" ];then
		  IP=$(get_public_ip $instance_id)
		  R53_record="roboshop.$DOMAIN"

		else
		  IP=$(get_private_ip $instance_id)
		  R53_record="roboshop.$instance.$DOMAIN"

		fi


		#Update Route 53 Records
	    update_route53_records $IP $R53_record
        
		RESOLVED_IP=$(aws route53 list-resource-record-sets \
                    --hosted-zone-id "$HOSTED_ZONE" \
                    --query "ResourceRecordSets[?Name=='$R53_record.'].ResourceRecords[0].Value" \
                    --output text)
					   
        if [ "$RESOLVED_IP" == "$ip" ]; then
		   echo "Route53 record verified!"
        else
            echo "Route53 record mismatch!"
        fi



	else
	   if [ "$instance_id" != "None" ];then
	      delete_instance $instance_id

		  aws ec2 wait instance-terminated \
		   --instance-ids $instance_id

		  instance_state=$(get_instance_state $instance_id)

		  if [ "$instance_state" == "terminated" ];then
              echo -e "$G Instance $instance_id terminated successfully! $N" 

		  else
		     echo -e "$R Instance termination failed! State: $instance_state $N"
			 exit 1
		  fi

	   else
	     echo "Instance with that name $instance doesn't exist nothing to do"

	   fi




	fi

	


done