#!/usr/bin/env bash
set -euo pipefail

POLICY_NAME="AWSLoadBalancerControllerIAMPolicy"

if [[ -z "${CLUSTER_NAME}" ]]; then
  echo "Usage: $0 <REGION> <CLUSTER_NAME> [AWS_ACCOUNT_ID]" >&2
  exit 1
fi

echo "Starting teardown..."

# Capture OIDC issuer (to try to delete OIDC provider later)
OIDC_ISSUER=$(aws eks describe-cluster --name "${CLUSTER_NAME}" --region "${REGION}" --query 'cluster.identity.oidc.issuer' --output text 2>/dev/null || echo "")

# 1) Uninstall AWS Load Balancer Controller (ignore errors)
echo "1) Uninstalling Helm release: aws-load-balancer-controller (kube-system)..."
helm uninstall aws-load-balancer-controller -n kube-system >/dev/null 2>&1 || true

# 2) Delete IRSA service account (removes IAM role created by eksctl)
echo "2) Deleting IRSA (iamserviceaccount) for aws-load-balancer-controller..."
eksctl delete iamserviceaccount \
  --cluster "${CLUSTER_NAME}" \
  --namespace kube-system \
  --name aws-load-balancer-controller \
  --wait || true

# 3) Detach & delete IAM policy created during install
echo "3) Detaching & deleting IAM policy (${POLICY_NAME}) if it exists..."
POLICY_ARN=$(aws iam list-policies --scope Local --query "Policies[?PolicyName=='${POLICY_NAME}'].Arn" --output text 2>/dev/null || true)
if [[ -n "${POLICY_ARN}" ]]; then
  echo "  Found policy: ${POLICY_ARN}"
  roles=$(aws iam list-entities-for-policy --policy-arn "${POLICY_ARN}" --query 'PolicyRoles[].RoleName' --output text 2>/dev/null || echo "")
  for r in $roles; do
    echo "  Detaching from role: $r"
    aws iam detach-role-policy --role-name "$r" --policy-arn "${POLICY_ARN}" || true
  done
  users=$(aws iam list-entities-for-policy --policy-arn "${POLICY_ARN}" --query 'PolicyUsers[].UserName' --output text 2>/dev/null || echo "")
  for u in $users; do
    echo "  Detaching from user: $u"
    aws iam detach-user-policy --user-name "$u" --policy-arn "${POLICY_ARN}" || true
  done
  groups=$(aws iam list-entities-for-policy --policy-arn "${POLICY_ARN}" --query 'PolicyGroups[].GroupName' --output text 2>/dev/null || echo "")
  for g in $groups; do
    echo "  Detaching from group: $g"
    aws iam detach-group-policy --group-name "$g" --policy-arn "${POLICY_ARN}" || true
  done
  vers=$(aws iam list-policy-versions --policy-arn "${POLICY_ARN}" --query 'Versions[?IsDefaultVersion==`false`].VersionId' --output text 2>/dev/null || echo "")
  for v in $vers; do
    echo "  Deleting policy version: $v"
    aws iam delete-policy-version --policy-arn "${POLICY_ARN}" --version-id "$v" || true
  done
  echo "  Deleting policy..."
  aws iam delete-policy --policy-arn "${POLICY_ARN}" || true
else
  echo "  Policy not found; skipping."
fi

# 4) Delete EKS cluster
echo "4) Deleting EKS cluster via eksctl (this can take a while)..."
eksctl delete cluster --name "${CLUSTER_NAME}" --region "${REGION}" --wait || true

# 5) Delete OIDC provider that matched this cluster
if [[ -n "${OIDC_ISSUER}" && "${OIDC_ISSUER}" != "None" ]]; then
  echo "5) Cleaning up IAM OIDC provider (if still present)..."
  for arn in $(aws iam list-open-id-connect-providers --query 'OpenIDConnectProviderList[].Arn' --output text 2>/dev/null); do
    url=$(aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$arn" --query 'Url' --output text 2>/dev/null || echo "")
    if [[ "$url" == "${OIDC_ISSUER#https://}" ]]; then
      echo "Deleting OIDC provider: $arn"
      aws iam delete-open-id-connect-provider --open-id-connect-provider-arn "$arn" || true
    fi
  done
fi

# 6) Prune kubeconfig contexts/users/clusters that reference the name
echo "6) Pruning kubeconfig entries for ${CLUSTER_NAME} (best-effort)..."
for ctx in $(kubectl config get-contexts -o name 2>/dev/null | grep -i "${CLUSTER_NAME}" || true); do
  kubectl config delete-context "$ctx" || true
done
kubectl config delete-cluster "${CLUSTER_NAME}" >/dev/null 2>&1 || true
kubectl config delete-user "${CLUSTER_NAME}" >/dev/null 2>&1 || true

echo "------------------------------------------------------------"
echo "Teardown complete. Some shared resources may not be removed."
