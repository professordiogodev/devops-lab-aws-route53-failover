#!/usr/bin/env bash
# Proves the lab left nothing in AWS. Run with: ./verify-teardown.sh
set -u
STUDENT=$(bash .lab/handle.sh) || exit 1
ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) || { echo "No working AWS credentials." >&2; exit 1; }
echo "Checking account $ACCOUNT, handle $STUDENT"
pass=0; failn=0
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then echo "PASS  $d"; pass=$((pass+1)); else echo "FAIL  $d"; failn=$((failn+1)); fi; }
empty() { local r; r=$(eval "$1" 2>/dev/null); [ -z "$r" ] || [ "$r" = None ]; }
check "no hosted zone lab-$STUDENT-$ACCOUNT.clippylab.net (a zone bills monthly)" empty "aws route53 list-hosted-zones --query \"HostedZones[?Name=='lab-$STUDENT-$ACCOUNT.clippylab.net.'].Id\" --output text"
check "no health check tagged student=$STUDENT" bash -c "for h in \$(aws route53 list-health-checks --query 'HealthChecks[].Id' --output text); do aws route53 list-tags-for-resource --resource-type healthcheck --resource-id \$h --query \"ResourceTagSet.Tags[?Key=='student'&&Value=='$STUDENT']\" --output text | grep -qx $STUDENT && exit 1; done; exit 0"
check "no running or stopped server tagged student=$STUDENT" empty "aws ec2 describe-instances --filters Name=tag:lab,Values=aws-route53-failover Name=tag:student,Values=$STUDENT Name=instance-state-name,Values=pending,running,stopping,stopped --query 'Reservations[].Instances[].InstanceId' --output text"
check "no Elastic IP tagged lab=aws-route53-failover (an unattached one bills)" empty "aws ec2 describe-addresses --filters Name=tag:lab,Values=aws-route53-failover Name=tag:student,Values=$STUDENT --query 'Addresses[].PublicIp' --output text"
check "no security group clippy-r53-$STUDENT" empty "aws ec2 describe-security-groups --filters Name=group-name,Values=clippy-r53-$STUDENT --query 'SecurityGroups[].GroupId' --output text"
echo
if [ "$failn" -eq 0 ]; then echo "TEARDOWN VERIFIED ($pass/$pass) in account $ACCOUNT"; else echo "NOT CLEAN: $failn leftover(s). Remove them and run this again."; fi
exit "$failn"
