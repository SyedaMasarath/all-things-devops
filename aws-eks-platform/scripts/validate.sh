#!/usr/bin/env bash
# =============================================================================
# Pre-deploy Validation Script
# Runs checks before Helm deploy to catch issues early
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
PASS="${GREEN}✓${NC}"; FAIL="${RED}✗${NC}"; WARN="${YELLOW}⚠${NC}"

ENVIRONMENT="${1:-dev}"
ERRORS=0

check() {
  local name="$1"
  local cmd="$2"
  if eval "$cmd" &>/dev/null; then
    echo -e "${PASS} ${name}"
  else
    echo -e "${FAIL} ${name}"
    ((ERRORS++))
  fi
}

echo ""
echo "================================================="
echo "  Pre-deploy Validation — Environment: ${ENVIRONMENT}"
echo "================================================="
echo ""

# --- Cluster connectivity ---
echo "📡 Cluster Connectivity"
check "kubectl can reach cluster" "kubectl cluster-info"
check "API server responsive" "kubectl get nodes --request-timeout=10s"

# --- Node readiness ---
echo ""
echo "🖥️  Node Health"
NODES_READY=$(kubectl get nodes --no-headers | grep -c "Ready" || true)
NODES_TOTAL=$(kubectl get nodes --no-headers | wc -l | tr -d ' ')
if [ "${NODES_READY}" -eq "${NODES_TOTAL}" ] && [ "${NODES_TOTAL}" -gt 0 ]; then
  echo -e "${PASS} All nodes ready (${NODES_READY}/${NODES_TOTAL})"
else
  echo -e "${FAIL} Not all nodes ready (${NODES_READY}/${NODES_TOTAL})"
  kubectl get nodes --no-headers | grep -v "Ready"
  ((ERRORS++))
fi

# --- Required namespaces ---
echo ""
echo "📦 Required Namespaces"
for ns in production monitoring applications; do
  check "Namespace '${ns}' exists" "kubectl get namespace ${ns}"
done

# --- Core components ---
echo ""
echo "⚙️  Core Components"
check "CoreDNS running" "kubectl get deployment coredns -n kube-system | grep -q Available"
check "AWS LB Controller running" "kubectl get deployment aws-load-balancer-controller -n kube-system | grep -q Available"
check "Cluster Autoscaler running" "kubectl get deployment cluster-autoscaler -n kube-system | grep -q Available"
check "EBS CSI Driver running" "kubectl get deployment ebs-csi-controller -n kube-system | grep -q Available"
check "External Secrets Operator" "kubectl get deployment external-secrets -n external-secrets | grep -q Available"

# --- Monitoring stack ---
echo ""
echo "📊 Monitoring Stack"
check "Prometheus running" "kubectl get statefulset prometheus-monitoring-prometheus -n monitoring | grep -q 2/2"
check "Grafana running" "kubectl get deployment monitoring-grafana -n monitoring | grep -q Available"
check "Alertmanager running" "kubectl get statefulset alertmanager-monitoring-alertmanager -n monitoring"

# --- Resource availability ---
echo ""
echo "🧮 Resource Headroom"
# Check that we have capacity for the deployment (basic check)
PENDING_PODS=$(kubectl get pods --all-namespaces --field-selector=status.phase=Pending --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "${PENDING_PODS}" -gt 0 ]; then
  echo -e "${WARN} ${PENDING_PODS} pending pods found — cluster may be resource constrained"
  kubectl get pods --all-namespaces --field-selector=status.phase=Pending --no-headers
else
  echo -e "${PASS} No pending pods — cluster has capacity"
fi

# --- Helm chart lint ---
echo ""
echo "🎯 Helm Validation"
check "Helm app-platform chart lints cleanly" "helm lint helm/charts/app-platform/"
check "Helm frontend chart lints cleanly" "helm lint helm/charts/frontend/"

# --- Results ---
echo ""
echo "================================================="
if [ "${ERRORS}" -eq 0 ]; then
  echo -e "${GREEN}✅ All validations passed! Proceeding with deployment.${NC}"
else
  echo -e "${RED}❌ ${ERRORS} validation(s) failed. Aborting deployment.${NC}"
  exit 1
fi
echo "================================================="
echo ""
