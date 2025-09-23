#!/bin/bash
REGION="us-west-2"

echo "--------------------------------------------------"
echo " AWS Monthly Service Cost Estimate Report "
echo "--------------------------------------------------"
printf "%-20s %-15s %-15s\n" "Service" "Usage" "Est. Monthly Cost"

# 1. EC2
EC2_INSTANCES=$(aws ec2 describe-instances \
  --region $REGION \
  --query "Reservations[*].Instances[*].[InstanceId,InstanceType,State.Name]" \
  --output text)

echo "$EC2_INSTANCES" | while read ID TYPE STATE; do
  HOURS=$((24*30)) # approx monthly
  case $TYPE in
    t2.micro) RATE=0.0116 ;;
    t3.medium) RATE=0.0416 ;;
    t3.large) RATE=0.0832 ;;
    t2.xlarge) RATE=0.1856 ;;
    m3.xlarge) RATE=0.266 ;;
    *) RATE=0 ;;
  esac
  COST=$(echo "$HOURS * $RATE" | bc)
  printf "%-20s %-15s $%.2f\n" "EC2 ($ID)" "$TYPE/$STATE" "$COST"
done

# 2. RDS
RDS_INSTANCES=$(aws rds describe-db-instances \
  --region $REGION \
  --query "DBInstances[*].[DBInstanceIdentifier,DBInstanceClass]" \
  --output text)

echo "$RDS_INSTANCES" | while read NAME CLASS; do
  HOURS=$((24*30))
  case $CLASS in
    db.t3.small) RATE=0.023 ;;
    db.t3.medium) RATE=0.046 ;;
    *) RATE=0 ;;
  esac
  COST=$(echo "$HOURS * $RATE" | bc)
  printf "%-20s %-15s $%.2f\n" "RDS ($NAME)" "$CLASS" "$COST"
done

# 3. CloudFront
CF_DIST=$(aws cloudfront list-distributions \
  --query "DistributionList.Items[*].Id" --output text)
for ID in $CF_DIST; do
  GB=$(aws cloudwatch get-metric-statistics \
    --namespace AWS/CloudFront \
    --metric-name BytesDownloaded \
    --dimensions Name=DistributionId,Value=$ID Name=Region,Value=Global \
    --start-time $(date -u -d "30 days ago" +%Y-%m-%dT%H:%M:%SZ) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
    --period 86400 --statistics Sum \
    --query "Datapoints[*].Sum" --output text)
  GB=$(echo "$GB/1073741824" | bc) # convert bytes to GB
  COST=$(echo "$GB * 0.085" | bc)
  printf "%-20s %-15s $%.2f\n" "CloudFront ($ID)" "$GB GB" "$COST"
done

# 4. Route 53 (hosted zones count)
HZ=$(aws route53 list-hosted-zones --query "HostedZones[*].Id" --output text | wc -w)
HZ_COST=$(echo "$HZ * 0.50" | bc)
printf "%-20s %-15s $%.2f\n" "Route53" "$HZ Zones" "$HZ_COST"

echo "--------------------------------------------------"
echo " Note: Costs are approximate (On-Demand rates only)"
echo "--------------------------------------------------"

