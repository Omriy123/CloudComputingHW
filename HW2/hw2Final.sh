# debug
# set -o xtrace

LB_KEY_NAME="load-balancer-`date +'%N'`"
LB_KEY_PEM="$LB_KEY_NAME.pem"

echo "create key pair $LB_KEY_PEM to connect to instances and save locally"
aws ec2 create-key-pair --key-name $LB_KEY_NAME \
    | jq -r ".KeyMaterial" > $LB_KEY_PEM

# secure the key pair
chmod 400 $LB_KEY_PEM

SEC_GRP="load-balancer-sg-`date +'%N'`"

echo "setup firewall for load-balancer $SEC_GRP"
aws ec2 create-security-group   \
                --group-name $SEC_GRP       \
                --description "Access my instances"

# figure out my ip
MY_IP=$(curl ipinfo.io/ip)
echo "My IP: $MY_IP"

echo "setup rule allowing SSH access to $MY_IP only"
aws ec2 authorize-security-group-ingress        \
    --group-name $SEC_GRP --port 22 --protocol tcp \
    --cidr $MY_IP/32

echo "setup rule allowing HTTP (port 5000) access to $MY_IP only for load balancer"
aws ec2 authorize-security-group-ingress        \
    --group-name $SEC_GRP --port 5000 --protocol tcp \
    --cidr $MY_IP/32


SEC_GRP_EP="endpoint-sg-`date +'%N'`"

echo "setup firewall for endpoint $SEC_GRP_EP"
aws ec2 create-security-group   \
                --group-name $SEC_GRP_EP       \
                --description "Access my instances"

echo "setup rule allowing HTTP from everywhere"
aws ec2 authorize-security-group-ingress        \
    --group-name $SEC_GRP_EP --port 5000 --protocol tcp \
    --cidr 0.0.0.0/0

echo "setup rule allowing SSH access to $MY_IP only for endpoints "
aws ec2 authorize-security-group-ingress        \
    --group-name $SEC_GRP_EP --port 22 --protocol tcp \
    --cidr $MY_IP/32

echo "setup rule allowing HTTP from the same sec group to load balacner"
aws ec2 authorize-security-group-ingress        \
    --group-name $SEC_GRP --port 5000 --protocol tcp \
    --source-group $SEC_GRP

echo "setup rule allowing HTTP from the endpoints sec group to loadbalancer"
aws ec2 authorize-security-group-ingress        \
    --group-name $SEC_GRP --port 5000 --protocol tcp \
    --source-group $SEC_GRP_EP



# trust policy json file
IAM_ROLE='ec2-iam-role'
echo "Creating iam role"
aws iam create-role --role-name $IAM_ROLE --assume-role-policy-document file://trust_policy.json

POLICY="$IAM_ROLE-policy"
echo "putting policy to role"
aws iam put-role-policy --role-name $IAM_ROLE --policy-name $POLICY --policy-document file://policy.json

echo "creating instnace profile"
aws iam create-instance-profile --instance-profile-name $IAM_ROLE

echo "attaching role to instance profile"
aws iam add-role-to-instance-profile --instance-profile-name $IAM_ROLE --role-name $IAM_ROLE


UBUNTU_20_04_AMI="ami-042e8287309f5df03"

echo "Creating Ubuntu 20.04 instance..."
LB_RUN_INSTANCES=$(aws ec2 run-instances   \
    --image-id $UBUNTU_20_04_AMI        \
    --instance-type t2.micro            \
    --key-name $LB_KEY_NAME                \
    --security-groups $SEC_GRP)

LB_INSTANCE_ID=$(echo $LB_RUN_INSTANCES | jq -r '.Instances[0].InstanceId')

echo "Waiting for instance creation..."
aws ec2 wait instance-running --instance-ids $LB_INSTANCE_ID

echo "associating iam instance profile to instance"
aws ec2 associate-iam-instance-profile --instance-id $LB_INSTANCE_ID --iam-instance-profile Name=$IAM_ROLE

LB_PUBLIC_IP=$(aws ec2 describe-instances  --instance-ids $LB_INSTANCE_ID | 
    jq -r '.Reservations[0].Instances[0].PublicIpAddress'
)
LB_PRIVATE_IP=$(aws ec2 describe-instances  --instance-ids $LB_INSTANCE_ID | 
    jq -r '.Reservations[0].Instances[0].PrivateIpAddress'
)

echo "New instance $LB_INSTANCE_ID @ $LB_PUBLIC_IP"

echo "deploying code to production"
scp -i $LB_KEY_PEM -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=60" loadbalancer.py ubuntu@$LB_PUBLIC_IP:/home/ubuntu/

#sudo apt-get install python3-pip
#pip install boto3

echo "setup production environment"
ssh -i $LB_KEY_PEM -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=10" ubuntu@$LB_PUBLIC_IP <<EOF
    sudo apt update
    sudo apt install python3-flask -y
    # run app
    export FLASK_APP=loadbalancer
    yes | sudo apt-get install python3-pip
    pip install boto3
    python3 loadbalancer.py &>/dev/null &
    # nohup flask run --host 0.0.0.0  &>/dev/null &
    exit
EOF

echo "test that it all worked"
curl  --retry-connrefused --retry 10 --retry-delay 1  http://$LB_PUBLIC_IP:5000

echo "*****************************"
echo "Creating endpoint 1"

EP1_KEY_NAME="endpoint-1-`date +'%N'`"
EP1_KEY_PEM="$EP1_KEY_NAME.pem"

echo "create key pair $EP1_KEY_PEM to connect to instances and save locally"
aws ec2 create-key-pair --key-name $EP1_KEY_NAME \
    | jq -r ".KeyMaterial" > $EP1_KEY_PEM

# secure the key pair
chmod 400 $EP1_KEY_PEM

echo "Creating Ubuntu 20.04 instance..."
EP1_RUN_INSTANCES=$(aws ec2 run-instances   \
    --image-id $UBUNTU_20_04_AMI        \
    --instance-type t2.micro            \
    --key-name $EP1_KEY_NAME                \
    --security-groups $SEC_GRP)

EP1_INSTANCE_ID=$(echo $EP1_RUN_INSTANCES | jq -r '.Instances[0].InstanceId')

echo "Waiting for instance creation..."
aws ec2 wait instance-running --instance-ids $EP1_INSTANCE_ID

EP1_PUBLIC_IP=$(aws ec2 describe-instances  --instance-ids $EP1_INSTANCE_ID | 
    jq -r '.Reservations[0].Instances[0].PublicIpAddress'
)

echo "New instance $EP1_INSTANCE_ID @ $EP1_PUBLIC_IP"

echo "deploying code to production"
scp -i $EP1_KEY_PEM -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=60" endpoint.py ubuntu@$EP1_PUBLIC_IP:/home/ubuntu/

echo "setup production environment"
ssh -i $EP1_KEY_PEM -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=10" ubuntu@$EP1_PUBLIC_IP <<EOF
    sudo apt update
    sudo apt install python3-flask -y
    # run app
    export LOADBALANCER_IP=$LB_PRIVATE_IP
    export FLASK_APP=endpoint
    nohup flask run --host 0.0.0.0  &>/dev/null &
    exit
EOF

echo "test that it all worked"
curl  --retry-connrefused --retry 10 --retry-delay 1  http://$EP1_PUBLIC_IP:5000


echo "*****************************"
echo "Creating endpoint 2"

EP2_KEY_NAME="endpoint-2-`date +'%N'`"
EP2_KEY_PEM="$EP2_KEY_NAME.pem"

echo "create key pair $EP2_KEY_PEM to connect to instances and save locally"
aws ec2 create-key-pair --key-name $EP2_KEY_NAME \
    | jq -r ".KeyMaterial" > $EP2_KEY_PEM

# secure the key pair
chmod 400 $EP2_KEY_PEM

echo "Creating Ubuntu 20.04 instance..."
EP2_RUN_INSTANCES=$(aws ec2 run-instances   \
    --image-id $UBUNTU_20_04_AMI        \
    --instance-type t2.micro            \
    --key-name $EP2_KEY_NAME                \
    --security-groups $SEC_GRP)

EP2_INSTANCE_ID=$(echo $EP2_RUN_INSTANCES | jq -r '.Instances[0].InstanceId')

echo "Waiting for instance creation..."
aws ec2 wait instance-running --instance-ids $EP2_INSTANCE_ID

EP2_PUBLIC_IP=$(aws ec2 describe-instances  --instance-ids $EP2_INSTANCE_ID | 
    jq -r '.Reservations[0].Instances[0].PublicIpAddress'
)

echo "New instance $EP2_INSTANCE_ID @ $EP2_PUBLIC_IP"

echo "deploying code to production"
scp -i $EP2_KEY_PEM -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=60" endpoint.py ubuntu@$EP2_PUBLIC_IP:/home/ubuntu/

echo "setup production environment"
ssh -i $EP2_KEY_PEM -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=10" ubuntu@$EP2_PUBLIC_IP <<EOF
    sudo apt update
    sudo apt install python3-flask -y
    # run app
    export LOADBALANCER_IP=$LB_PRIVATE_IP
    export FLASK_APP=endpoint
    nohup flask run --host 0.0.0.0  &>/dev/null &
    exit
EOF

echo "test that it all worked"
curl  --retry-connrefused --retry 10 --retry-delay 1  http://$EP2_PUBLIC_IP:5000