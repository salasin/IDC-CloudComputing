# Branched from https://gist.github.com/ayende/db14de14bcd4e0603eb30f26914d9a2b

KEY_NAME="key-`date +'%N'`"
KEY_PEM="$KEY_NAME.pem"
UBUNTU_20_04_AMI="ami-042e8287309f5df03"
REDIS_SERVING_PORT=6379
ENDPOINT_SERVING_PORT=5000
MY_IP=$(curl ipinfo.io/ip)
ACCESS_KEY_ID=""
SECRET_ACCESS_KEY=""
AVAILABILITY_ZONE="us-east-1a"

echo "create key pair $KEY_PEM to connect to instances and save locally"
aws ec2 create-key-pair --key-name $KEY_NAME \
    | jq -r ".KeyMaterial" > $KEY_PEM
# secure the key pair
chmod 400 $KEY_PEM

########################################################################################################################
#
# SETUP OF REDIS SERVER
#
########################################################################################################################

REDIS_SEC_GRP="redis-sg-`date +'%N'`"

echo "setup security group for Redis server..."
aws ec2 create-security-group   \
    --group-name $REDIS_SEC_GRP       \
    --description "Redis server security group"

echo "setup rule allowing SSH access to Redis server..."
aws ec2 authorize-security-group-ingress        \
    --group-name $REDIS_SEC_GRP --port 22 --protocol tcp \
    --cidr $MY_IP/32

echo "setup rule allowing HTTP (port $REDIS_SERVING_PORT) access to Redis server..."
aws ec2 authorize-security-group-ingress        \
    --group-name $REDIS_SEC_GRP --port $REDIS_SERVING_PORT --protocol tcp \
    --cidr 0.0.0.0/0

echo "creating Redis server..."
RUN_REDIS_SERVER=$(aws ec2 run-instances   \
    --image-id $UBUNTU_20_04_AMI        \
    --instance-type t3.micro            \
    --key-name $KEY_NAME                \
    --security-groups $REDIS_SEC_GRP)

REDIS_SERVER_INSTANCE_ID=$(echo $RUN_REDIS_SERVER | jq -r '.Instances[0].InstanceId')

aws ec2 wait instance-running --instance-ids $REDIS_SERVER_INSTANCE_ID

REDIS_SERVER_IP=$(aws ec2 describe-instances  --instance-ids $REDIS_SERVER_INSTANCE_ID |
    jq -r '.Reservations[0].Instances[0].PublicIpAddress'
)

echo "Redis server $REDIS_SERVER_INSTANCE_ID @ $REDIS_SERVER_IP"

# TODO: this doesn't work when it's running from a script, only when the commands are run manually
echo "setup Redis server..."
ssh -i $KEY_PEM -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=10" ubuntu@$REDIS_SERVER_IP <<EOF
    sudo apt-get update
    yes Y | sudo apt-get install redis-server
    sudo service redis-server stop
    redis-server --port $REDIS_SERVING_PORT --daemonize yes --protected-mode no
    exit
EOF

########################################################################################################################
#
# SETUP OF ENDPOINT SERVERS
#
########################################################################################################################

ENDPOINT_SERVER_SEC_GRP="endpoint-server-sg-`date +'%N'`"

echo "setup security group for endpoint server..."
aws ec2 create-security-group   \
    --group-name $ENDPOINT_SERVER_SEC_GRP      \
    --description "Endpoint server security group"

echo "setup rule allowing SSH access to endpoint servers"
aws ec2 authorize-security-group-ingress        \
    --group-name $ENDPOINT_SERVER_SEC_GRP --port 22 --protocol tcp \
    --cidr $MY_IP/32

echo "setup rule allowing HTTP (port $ENDPOINT_SERVING_PORT) access to endpoint server"
aws ec2 authorize-security-group-ingress        \
    --group-name $ENDPOINT_SERVER_SEC_GRP --port $ENDPOINT_SERVING_PORT --protocol tcp \
    --cidr 0.0.0.0/0

echo "creating primary endpoint server..."
RUN_PRIMARY_ENDPOINT_SERVER=$(aws ec2 run-instances   \
    --image-id $UBUNTU_20_04_AMI        \
    --instance-type t3.micro            \
    --key-name $KEY_NAME                \
    --security-groups $ENDPOINT_SERVER_SEC_GRP)

PRIMARY_ENDPOINT_SERVER_INSTANCE_ID=$(echo $RUN_PRIMARY_ENDPOINT_SERVER | jq -r '.Instances[0].InstanceId')

aws ec2 wait instance-running --instance-ids $PRIMARY_ENDPOINT_SERVER_INSTANCE_ID

PRIMARY_ENDPOINT_SERVER_IP=$(aws ec2 describe-instances  --instance-ids $PRIMARY_ENDPOINT_SERVER_INSTANCE_ID |
    jq -r '.Reservations[0].Instances[0].PublicIpAddress'
)

echo "primary endpoint server $PRIMARY_ENDPOINT_SERVER_INSTANCE_ID @ $PRIMARY_ENDPOINT_SERVER_IP"

echo "deploying code to primary endpoint server"
scp -i $KEY_PEM -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=60" endpoint.py ubuntu@$PRIMARY_ENDPOINT_SERVER_IP:/home/ubuntu/

echo "setup primary endpoint server..."
ssh -i $KEY_PEM -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=10" ubuntu@$PRIMARY_ENDPOINT_SERVER_IP <<EOF
    sudo apt-get update
    sudo apt-get install python3-flask -y
    yes Y | sudo apt-get install python3-pip
    pip3 install redis
    pip3 install apscheduler
    pip3 install boto3
    nohup python3 endpoint.py $REDIS_SERVER_IP primary $ACCESS_KEY_ID $SECRET_ACCESS_KEY &>/dev/null &
    exit
EOF

echo "creating secondary endpoint server..."
RUN_SECONDARY_ENDPOINT_SERVER=$(aws ec2 run-instances   \
    --image-id $UBUNTU_20_04_AMI        \
    --instance-type t3.micro            \
    --key-name $KEY_NAME                \
    --security-groups $ENDPOINT_SERVER_SEC_GRP)

SECONDARY_ENDPOINT_SERVER_INSTANCE_ID=$(echo $RUN_SECONDARY_ENDPOINT_SERVER | jq -r '.Instances[0].InstanceId')

echo "waiting for secondary endpoint server creation..."
aws ec2 wait instance-running --instance-ids $SECONDARY_ENDPOINT_SERVER_INSTANCE_ID

SECONDARY_ENDPOINT_SERVER_IP=$(aws ec2 describe-instances  --instance-ids $SECONDARY_ENDPOINT_SERVER_INSTANCE_ID |
    jq -r '.Reservations[0].Instances[0].PublicIpAddress'
)

echo "secondary endpoint server $SECONDARY_ENDPOINT_SERVER_INSTANCE_ID @ $SECONDARY_ENDPOINT_SERVER_IP"

echo "deploying code to secondary endpoint server"
scp -i $KEY_PEM -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=60" endpoint.py ubuntu@$SECONDARY_ENDPOINT_SERVER_IP:/home/ubuntu/

echo "setup secondary endpoint server..."
ssh -i $KEY_PEM -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=10" ubuntu@$SECONDARY_ENDPOINT_SERVER_IP <<EOF
    sudo apt update
    sudo apt install python3-flask -y
    python3 endpoint.py $REDIS_SERVER_IP secondary
    exit
EOF

########################################################################################################################
#
# SETUP OF WORKERS
#
########################################################################################################################

WORKER_SERVER_SEC_GRP="worker-server-sg-`date +'%N'`"

echo "setup security group for worker server..."
aws ec2 create-security-group   \
    --group-name $WORKER_SERVER_SEC_GRP      \
    --description "Worker server security group"

echo "setup rule allowing SSH access to worker servers"
aws ec2 authorize-security-group-ingress        \
    --group-name $WORKER_SERVER_SEC_GRP --port 22 --protocol tcp \
    --cidr $MY_IP/32

echo '#!/bin/bash' > userdata
echo 'cd /root' >> userdata
echo 'REDIS_SERVER_IP='$REDIS_SERVER_IP >> userdata
echo 'sudo apt-get update' >> userdata
echo 'sudo apt-get install -y python3-pip' >> userdata
echo 'sudo apt-get install -y git-all' >> userdata
echo 'pip3 install redis' >> userdata
echo 'git clone "https://github.com/salasin/IDC-CloudComputing"' >> userdata
echo 'python3 IDC-CloudComputing/HW2/worker.py $REDIS_SERVER_IP' >> userdata

aws autoscaling create-launch-configuration \
    --launch-configuration-name worker-lc \
    --image-id $UBUNTU_20_04_AMI \
    --instance-type t3.micro \
    --key-name $KEY_NAME \
    --security-groups $WORKER_SERVER_SEC_GRP \
    --user-data file://userdata

rm userdata

#VPC=$(aws ec2 describe-security-groups --group-names $WORKER_SERVER_SEC_GRP |
#    jq -r '.SecurityGroups[0].VpcId'
#)

# TODO: determine $AVAILABILITY_ZONE dynamically

aws autoscaling create-auto-scaling-group --auto-scaling-group-name workers-asg \
  --launch-configuration-name worker-lc \
  --availability-zones $AVAILABILITY_ZONE \
  --max-size 1 --min-size 0

START_POLICY_ARN=$(aws autoscaling put-scaling-policy --policy-name start-worker-policy \
  --auto-scaling-group-name workers-asg --scaling-adjustment 1 \
  --adjustment-type ChangeInCapacity | jq -r '.PolicyARN'
)

STOP_POLICY_ARN=$(aws autoscaling put-scaling-policy --policy-name stop-worker-policy \
  --auto-scaling-group-name workers-asg --scaling-adjustment -1 \
  --adjustment-type ChangeInCapacity --cooldown 300 | jq -r '.PolicyARN'
)

aws cloudwatch put-metric-alarm --alarm-name start-worker-alarm \
  --metric-name work_queue_length --namespace CloudComputingHW2 --statistic Average \
  --period 60 --evaluation-periods 5 --threshold 0.001 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --alarm-actions $START_POLICY_ARN

aws cloudwatch put-metric-alarm --alarm-name stop-worker-alarm \
  --metric-name work_queue_length --namespace CloudComputingHW2 --statistic Average \
  --period 180 --evaluation-periods 15 --threshold 0.001 \
  --comparison-operator LessThanThreshold \
  --alarm-actions $STOP_POLICY_ARN