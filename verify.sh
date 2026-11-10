#!/usr/bin/env bash
# Reads your zone, records and health check, and asks Route 53 what it answers. Run with: ./verify.sh
cd "$(dirname "$0")" || exit 1
ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) || { echo "No working AWS credentials." >&2; exit 1; }
exec python3 .lab/awscheck.py "$ACCOUNT"
