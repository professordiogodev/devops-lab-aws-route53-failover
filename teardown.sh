#!/usr/bin/env bash
# Deletes the records, the health checks, the hosted zone, the servers and the Elastic IPs. Run with: ./teardown.sh
set -u
ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) || { echo "No working AWS credentials." >&2; exit 1; }
L=aws-route53-failover
Z="lab-$ACCOUNT.clippylab.net."
for ZID in $(aws route53 list-hosted-zones-by-name --dns-name "$Z" --max-items 1 --query "HostedZones[?Name=='$Z'].Id" --output text); do
  python3 - "$ZID" <<'PY'
import json, subprocess, sys
z = sys.argv[1]
rr = json.loads(subprocess.check_output(["aws", "route53", "list-resource-record-sets", "--hosted-zone-id", z, "--output", "json"]))["ResourceRecordSets"]
ch = [{"Action": "DELETE", "ResourceRecordSet": r} for r in rr if r["Type"] not in ("NS", "SOA")]
if ch:
    subprocess.check_call(["aws", "route53", "change-resource-record-sets", "--hosted-zone-id", z, "--change-batch", json.dumps({"Changes": ch})], stdout=subprocess.DEVNULL)
    print("deleted", len(ch), "record(s)")
PY
  aws route53 delete-hosted-zone --id "$ZID" >/dev/null && echo "deleted hosted zone $Z"
done
for H in $(aws route53 list-health-checks --query 'HealthChecks[].Id' --output text); do
  if aws route53 list-tags-for-resource --resource-type healthcheck --resource-id $H --query "ResourceTagSet.Tags[?Key=='lab'&&Value=='$L']" --output text | grep -q $L; then aws route53 delete-health-check --health-check-id $H && echo "deleted health check $H"; fi
done
IDS=$(aws ec2 describe-instances --filters Name=tag:lab,Values=$L Name=instance-state-name,Values=pending,running,stopping,stopped --query 'Reservations[].Instances[].InstanceId' --output text)
[ -n "$IDS" ] && aws ec2 terminate-instances --instance-ids $IDS >/dev/null && aws ec2 wait instance-terminated --instance-ids $IDS && echo "terminated $IDS"
for a in $(aws ec2 describe-addresses --filters Name=tag:lab,Values=$L --query 'Addresses[].AllocationId' --output text); do aws ec2 release-address --allocation-id $a && echo "released Elastic IP $a"; done
for _ in 1 2 3 4 5 6; do
  ids=$(aws ec2 describe-security-groups --filters Name=group-name,Values=clippy-r53 --query 'SecurityGroups[].GroupId' --output text)
  [ -z "$ids" ] && break
  for g in $ids; do aws ec2 delete-security-group --group-id $g >/dev/null 2>&1 && echo "deleted security group"; done
  sleep 6
done
echo "Now run ./verify-teardown.sh"
