#!/usr/bin/env python3
import json, os, subprocess, sys
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
os.chdir(ROOT)
ACCOUNT = sys.argv[1]
ZONE = "lab-%s.clippylab.net." % ACCOUNT
NAME = "app." + ZONE
passed = failed = 0


def check(desc, ok, hint=""):
    global passed, failed
    if ok:
        passed += 1; print("PASS  " + desc)
    else:
        failed += 1; print("FAIL  " + desc + (("   -> " + hint) if hint else ""))


def aws(*a):
    try:
        return json.loads(subprocess.check_output(("aws",) + a + ("--output", "json"), stderr=subprocess.DEVNULL, timeout=60) or "null")
    except Exception:
        return None


check("no AWS keys in the repository", subprocess.run("git grep -lE 'AKIA[0-9A-Z]{16}' -- . ':!.lab' ':!verify.sh'", shell=True, capture_output=True, text=True).stdout.strip() == "")
print("== The servers ==")
ins = {}
for r in (aws("ec2", "describe-instances", "--filters", "Name=tag:lab,Values=aws-route53-failover", "Name=instance-state-name,Values=pending,running,stopping,stopped") or {}).get("Reservations", []):
    for i in r["Instances"]:
        role = next((t["Value"] for t in i.get("Tags", []) if t["Key"] == "Role"), "?")
        ins[role] = i
adr = {a["InstanceId"]: a["PublicIp"] for a in (aws("ec2", "describe-addresses", "--filters", "Name=tag:lab,Values=aws-route53-failover") or {}).get("Addresses", []) if a.get("InstanceId")}
ip = {role: adr.get(i["InstanceId"]) for role, i in ins.items()}
check("primary and secondary servers exist with their Elastic IPs", sorted(ins) == ["primary", "secondary"] and all(ip.values()), "./setup.sh")
print("== The hosted zone ==")
zones = [z for z in (aws("route53", "list-hosted-zones-by-name", "--dns-name", ZONE, "--max-items", "1") or {}).get("HostedZones", []) if z["Name"] == ZONE]
check("a public hosted zone called %s exists" % ZONE, len(zones) == 1 and not zones[0]["Config"].get("PrivateZone"))
if not zones or sorted(ins) != ["primary", "secondary"]:
    print("\nNothing else can be checked.\n%d check(s) failed, %d passed" % (failed, passed)); sys.exit(1)
zid = zones[0]["Id"].split("/")[-1]
rr = [r for r in (aws("route53", "list-resource-record-sets", "--hosted-zone-id", zid) or {}).get("ResourceRecordSets", []) if r["Name"] == NAME and r["Type"] == "A"]
pri = next((r for r in rr if r.get("Failover") == "PRIMARY"), None)
sec = next((r for r in rr if r.get("Failover") == "SECONDARY"), None)
check("%s has a PRIMARY and a SECONDARY failover A record" % NAME.rstrip("."), bool(pri) and bool(sec), "found %d record(s)" % len(rr))
check("PRIMARY points to the primary server's Elastic IP and SECONDARY to the secondary's",
      bool(pri) and bool(sec) and [x["Value"] for x in pri["ResourceRecords"]] == [ip["primary"]] and [x["Value"] for x in sec["ResourceRecords"]] == [ip["secondary"]])
check("both records have a TTL of 60 seconds or less", bool(pri) and bool(sec) and pri["TTL"] <= 60 and sec["TTL"] <= 60)
check("the PRIMARY record is tied to a health check", bool(pri) and bool(pri.get("HealthCheckId")))
hc = (aws("route53", "get-health-check", "--health-check-id", pri["HealthCheckId"]) or {}).get("HealthCheck", {}).get("HealthCheckConfig", {}) if pri and pri.get("HealthCheckId") else {}
check("the health check is HTTP on port 80, path /healthz, against the primary's Elastic IP", hc.get("Type") == "HTTP" and hc.get("Port") == 80 and hc.get("ResourcePath") == "/healthz" and hc.get("IPAddress") == ip["primary"])
worst = hc.get("RequestInterval", 30) * hc.get("FailureThreshold", 3) if hc else 999
check("the health check detects a failure within 40 seconds (interval x failure threshold = %ss)" % worst, worst <= 40, "use RequestInterval 10 and FailureThreshold 2 or 3")
print("== What Route 53 answers ==")
def answer():
    a = aws("route53", "test-dns-answer", "--hosted-zone-id", zid, "--record-name", NAME.rstrip("."), "--record-type", "A")
    return (a or {}).get("RecordData", [None])[0] if a else None
state = ins["primary"]["State"]["Name"]
ans = answer()
if state == "running":
    st = ((aws("route53", "get-health-check-status", "--health-check-id", pri["HealthCheckId"]) or {}).get("HealthCheckObservations") or [{}])[0].get("StatusReport", {}).get("Status", "") if pri else ""
    check("primary is running and healthy: Route 53 answers with the PRIMARY address", ans == ip["primary"] and st.startswith("Success"), "answer %s, health: %s" % (ans, st[:40]))
else:
    check("primary is %s: Route 53 answers with the SECONDARY address" % state, ans == ip["secondary"], "answer %s" % ans)
import datetime
pts = []
if pri and pri.get("HealthCheckId"):
    now = datetime.datetime.utcnow()
    st = (now - datetime.timedelta(hours=6)).strftime("%Y-%m-%dT%H:%M:%SZ")
    en = now.strftime("%Y-%m-%dT%H:%M:%SZ")
    d = aws("cloudwatch", "get-metric-statistics", "--region", "us-east-1", "--namespace", "AWS/Route53", "--metric-name", "HealthCheckStatus",
            "--dimensions", "Name=HealthCheckId,Value=" + pri["HealthCheckId"], "--start-time", st, "--end-time", en, "--period", "60", "--statistics", "Minimum")
    pts = [x["Minimum"] for x in sorted((d or {}).get("Datapoints", []), key=lambda x: x["Timestamp"])]
seen_up = False; went_down = False
for v in pts:
    if v >= 1:
        seen_up = True
    elif seen_up:
        went_down = True
check("the health check went from healthy to UNHEALTHY at some point (you really stopped the primary; CloudWatch can lag 3-5 minutes)", went_down, "stop the primary, ask Route 53, wait a few minutes, run again")
print()
print(("ALL CHECKS PASSED (%d/%d)" % (passed, passed)) if failed == 0 else ("%d check(s) failed, %d passed" % (failed, passed)))
sys.exit(1 if failed else 0)
