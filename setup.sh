#!/usr/bin/env bash
# Launches the two servers (primary and secondary) with fixed Elastic IPs. Run once: ./setup.sh
set -u
cd "$(dirname "$0")"
ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) || { echo "No working AWS credentials." >&2; exit 1; }
L=aws-route53-failover
if aws ec2 describe-instances --filters Name=tag:lab,Values=$L Name=instance-state-name,Values=pending,running,stopped --query 'Reservations[].Instances[].InstanceId' --output text | grep -q 'i-'; then echo "The servers already exist."; exit 0; fi
VPC=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)
[ "$VPC" != None ] || { echo "No default VPC in this region." >&2; exit 1; }
SUBNET=$(aws ec2 describe-subnets --filters Name=vpc-id,Values=$VPC Name=map-public-ip-on-launch,Values=true --query 'Subnets[0].SubnetId' --output text)
SG=$(aws ec2 create-security-group --group-name clippy-r53 --description "Clippy failover lab" --vpc-id $VPC --tag-specifications "ResourceType=security-group,Tags=[{Key=lab,Value=$L}]" --query GroupId --output text)
aws ec2 authorize-security-group-ingress --group-id $SG --protocol tcp --port 80 --cidr 0.0.0.0/0 >/dev/null
AMI=$(aws ssm get-parameter --name /aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id --query Parameter.Value --output text)
launch() { # role
  sed "s/ROLE_NAME/$1/" userdata.sh.tpl > .userdata-$1.sh
  aws ec2 run-instances --image-id $AMI --instance-type t3.micro --subnet-id $SUBNET --security-group-ids $SG \
    --user-data file://.userdata-$1.sh --metadata-options HttpTokens=required,HttpEndpoint=enabled \
    --tag-specifications "ResourceType=instance,Tags=[{Key=lab,Value=$L},{Key=Name,Value=clippy-$1},{Key=Role,Value=$1}]" --query 'Instances[0].InstanceId' --output text
}
P=$(launch primary); S=$(launch secondary)
rm -f .userdata-*.sh
aws ec2 wait instance-running --instance-ids $P $S
for pair in "$P primary" "$S secondary"; do
  set -- $pair
  A=$(aws ec2 allocate-address --domain vpc --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=lab,Value=$L},{Key=Name,Value=clippy-$2}]" --query AllocationId --output text)
  aws ec2 associate-address --instance-id $1 --allocation-id $A >/dev/null
done
IP1=$(aws ec2 describe-addresses --filters Name=tag:Name,Values=clippy-primary --query 'Addresses[0].PublicIp' --output text)
IP2=$(aws ec2 describe-addresses --filters Name=tag:Name,Values=clippy-secondary --query 'Addresses[0].PublicIp' --output text)
echo "primary   $P  $IP1  (Elastic IP, stays the same after a stop and start)"
echo "secondary $S  $IP2"
echo "Clippy needs two minutes to install: http://$IP1/healthz   (the 'version' field says which server answered)"
echo "Your hosted zone must be called: lab-$ACCOUNT.clippylab.net"
