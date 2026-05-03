# Runbook: Production Incident Response

## Severity Definitions

| Sev | Impact | Response Time | Example |
|-----|--------|--------------|---------|
| P1 | Production down / data loss | 15 min | API returning 5xx for all users |
| P2 | Degraded performance | 30 min | Latency > 2x SLA, partial outage |
| P3 | Minor issue | 4 hours | Non-critical service degraded |
| P4 | No user impact | Next business day | Monitoring gap, config drift |

---

## High Pod Restart Count

**Alert**: `KubePodCrashLooping`

```bash
# 1. Identify crashing pods
kubectl get pods -n production | grep -E "CrashLoop|Error|OOMKilled"

# 2. Get logs from crashing container (including previous crash)
kubectl logs <pod-name> -n production --previous --tail=100

# 3. Describe pod for events
kubectl describe pod <pod-name> -n production

# 4. Check resource limits (OOM?)
kubectl top pods -n production

# 5. If OOMKilled — bump memory limits temporarily
kubectl set resources deployment/<name> -n production \
  --limits=memory=1Gi --requests=memory=512Mi
```

---

## Node Not Ready

**Alert**: `KubeNodeNotReady`

```bash
# 1. Check node status
kubectl get nodes -o wide
kubectl describe node <node-name>

# 2. Check node conditions
kubectl get node <node-name> -o jsonpath='{.status.conditions}'

# 3. SSH via SSM (no bastion needed)
aws ssm start-session --target <instance-id>

# 4. Check kubelet on node
sudo systemctl status kubelet
sudo journalctl -u kubelet -n 100

# 5. If node is unrecoverable — cordon and drain
kubectl cordon <node-name>
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data --force
# Node will be replaced by Cluster Autoscaler

# 6. Verify pods rescheduled
kubectl get pods -n production -o wide | grep <node-name>
```

---

## High Latency / 5xx Errors

**Alert**: `HighErrorRate`, `HighLatency`

```bash
# 1. Check pod status
kubectl get pods -n production
kubectl top pods -n production

# 2. Check HPA status (are we at max replicas?)
kubectl get hpa -n production

# 3. Check ALB access logs in CloudWatch
aws logs filter-log-events \
  --log-group-name /aws/alb/eks-platform-prod \
  --filter-pattern "5??" \
  --start-time $(date -d '15 minutes ago' +%s)000

# 4. Check pod logs for errors
kubectl logs -l app.kubernetes.io/name=api-service \
  -n production --tail=200 | grep -E "ERROR|FATAL|panic"

# 5. Rollback if recent deployment caused this
helm rollback api-service -n production
helm history api-service -n production  # see revision history

# 6. Scale up manually if autoscaler isn't responding fast enough
kubectl scale deployment api-service -n production --replicas=10
```

---

## Database Connection Issues

```bash
# 1. Test DB connectivity from a pod
kubectl run debug --rm -it --image=postgres:15-alpine \
  --restart=Never -n production -- \
  psql -h <rds-endpoint> -U platform_admin -d platform -c "SELECT 1"

# 2. Check RDS metrics in CloudWatch
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --dimensions Name=DBClusterIdentifier,Value=eks-platform-prod \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average

# 3. Check External Secrets (are DB creds fresh?)
kubectl get externalsecret -n production
kubectl describe externalsecret db-credentials -n production
```

---

## Cluster Autoscaler Not Scaling

```bash
# 1. Check CA logs
kubectl logs -l app.kubernetes.io/name=cluster-autoscaler \
  -n kube-system --tail=100

# 2. Check pending pods (trigger for scale-up)
kubectl get pods --all-namespaces --field-selector=status.phase=Pending

# 3. Check CA status
kubectl describe configmap cluster-autoscaler-status -n kube-system

# 4. Verify node group limits in AWS
aws autoscaling describe-auto-scaling-groups \
  --query 'AutoScalingGroups[?starts_with(AutoScalingGroupName, `eks-platform-prod`)].{Name:AutoScalingGroupName,Min:MinSize,Max:MaxSize,Desired:DesiredCapacity}'
```

---

## Useful One-liners

```bash
# All unhealthy pods
kubectl get pods --all-namespaces | grep -v "Running\|Completed"

# Pods sorted by restart count
kubectl get pods -A --sort-by='.status.containerStatuses[0].restartCount'

# Recent events (warnings only)
kubectl get events -A --field-selector type=Warning --sort-by='.lastTimestamp'

# Resource usage by namespace
kubectl top pods -A --sort-by=memory

# Force delete stuck terminating pod
kubectl delete pod <name> -n <ns> --force --grace-period=0

# Check IRSA token is valid for a pod
kubectl exec -n <ns> <pod> -- cat /var/run/secrets/eks.amazonaws.com/serviceaccount/token | \
  cut -d. -f2 | base64 -d 2>/dev/null | jq .
```
