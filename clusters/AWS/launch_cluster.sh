#!/usr/bin/env bash
set -euo pipefail

# ---- Create a throwaway rendered config ----
TMP_CFG="$(mktemp -t eksctl-cluster-XXXXXX.yaml)"
trap 'rm -f "$TMP_CFG"' EXIT

echo "Rendering template to temporary file: $TMP_CFG"
envsubst < "$TEMPLATE" > "$TMP_CFG"

echo "Creating EKS cluster + node groups with eksctl…"
eksctl create cluster -f "$TMP_CFG"

echo "Updating kubeconfig…"
aws eks --region "${REGION}" update-kubeconfig --name "${CLUSTER_NAME}"

# Wait until CoreDNS is running and has endpoints (Required before ALB)
kubectl -n kube-system rollout status deploy/coredns --timeout=5m
kubectl -n kube-system get endpoints kube-dns | grep -qE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:' || \
  (echo "CoreDNS endpoints not ready"; exit 1)

eksctl utils associate-iam-oidc-provider --cluster "${CLUSTER_NAME}" --region "${REGION}" --approve

# ------------ ALB Controller IAM ------------
ALB_SA=${ALB_SA:-aws-load-balancer-controller}
ALB_ROLE=${ALB_ROLE:-ALBControllerPodIdentityRole}
POLICY_NAME=${POLICY_NAME:-AWSLoadBalancerControllerIAMPolicy}
HELM_CHART_VERSION_FLAG=${HELM_CHART_VERSION:+--version "$HELM_CHART_VERSION"}

# Discover controller appVersion from the helm chart
ALB_APP_VERSION=$(helm show chart eks/aws-load-balancer-controller $HELM_CHART_VERSION_FLAG \
  | awk -F': ' '/^appVersion:/ {print $2; exit}')
if [[ -z "$ALB_APP_VERSION" || "$ALB_APP_VERSION" == "None" ]]; then
  echo "ERROR: could not determine aws-load-balancer-controller appVersion from Helm chart." >&2
  exit 1
fi
echo "Controller appVersion = ${ALB_APP_VERSION}"

POLICY_DOC_URL="https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/${ALB_APP_VERSION}/docs/install/iam_policy.json"
curl -fsSL -o alb-iam-policy.json "$POLICY_DOC_URL" || { echo "ERROR: failed to fetch $POLICY_DOC_URL" >&2; exit 1; }

# Find existing customer-managed policy (if any)
POL_ARN=$(aws iam list-policies --scope Local \
  --query "Policies[?PolicyName=='${POLICY_NAME}']|[0].Arn" --output text 2>/dev/null)
if [[ -z "$POL_ARN" || "$POL_ARN" == "None" ]]; then
  # Create it if missing
  POL_ARN=$(aws iam create-policy \
    --policy-name "${POLICY_NAME}" \
    --policy-document file://alb-iam-policy.json \
    --query 'Policy.Arn' --output text) || { echo "ERROR: create-policy failed"; exit 1; }
  echo "Created policy ${POLICY_NAME}: ${POL_ARN}"
else
  #Update existing policy by creating a new version and set as default
  #delete an old non-default if you’re at the limit (Limit of 5).
  VER_COUNT=$(aws iam list-policy-versions --policy-arn "$POL_ARN" --query 'length(Versions)' --output text)
  if [[ "$VER_COUNT" -ge 5 ]]; then
    OLD_VER=$(aws iam list-policy-versions --policy-arn "$POL_ARN" \
      --query "Versions[?IsDefaultVersion==\`false\`]|[-1].VersionId" --output text)
    [[ -n "$OLD_VER" && "$OLD_VER" != "None" ]] && \
      aws iam delete-policy-version --policy-arn "$POL_ARN" --version-id "$OLD_VER"
  fi
  aws iam create-policy-version --policy-arn "$POL_ARN" \
    --policy-document file://alb-iam-policy.json --set-as-default >/dev/null
  echo "Updated policy ${POLICY_NAME} to match controller ${ALB_APP_VERSION}"
fi

# Guard
if [[ -z "$POL_ARN" || "$POL_ARN" == "None" || ${#POL_ARN} -lt 20 ]]; then
  echo "ERROR: Invalid ALB policy ARN: '${POL_ARN}'" >&2
  exit 1
fi

# Ensure role exists and has policy attached (EKS Pod Identity trust)
echo "ensuring ALB Role"
if ! aws iam get-role --role-name "$ALB_ROLE" >/dev/null 2>&1; then
  cat > trust-alb-pod-identity.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "pods.eks.amazonaws.com" },
    "Action": [ "sts:AssumeRole", "sts:TagSession" ]
  }]
}
EOF
  aws iam create-role \
    --role-name "$ALB_ROLE" \
    --assume-role-policy-document file://trust-alb-pod-identity.json >/dev/null
fi

ATTACHED=$(aws iam list-attached-role-policies --role-name "$ALB_ROLE" \
  --query "AttachedPolicies[?PolicyArn=='${POL_ARN}']|length(@)" --output text)
if [[ "$ATTACHED" != "1" ]]; then
  aws iam attach-role-policy --role-name "$ALB_ROLE" --policy-arn "$POL_ARN"
fi

# Create the kube SA
echo "Creating kube SA"
kubectl -n kube-system get sa "$ALB_SA" >/dev/null 2>&1 || \
kubectl -n kube-system create sa "$ALB_SA"

# Create the Pod Identity association
echo "🔗 Create (or re-point) the Pod Identity association"
ALB_ROLE_ARN=$(aws iam get-role --role-name "$ALB_ROLE" --query 'Role.Arn' --output text)
EXISTING=$(aws eks list-pod-identity-associations --cluster-name "$CLUSTER_NAME" --region "$REGION" \
  --query "associations[?namespace=='kube-system' && serviceAccount=='$ALB_SA'].associationId" --output text || true)
if [[ -z "$EXISTING" ]]; then
  aws eks create-pod-identity-association \
    --cluster-name "$CLUSTER_NAME" \
    --namespace kube-system \
    --service-account "$ALB_SA" \
    --role-arn "$ALB_ROLE_ARN" \
    --region "$REGION" >/dev/null
fi

echo "Installing AWS Load Balance Controller"
helm repo add eks https://aws.github.io/eks-charts >/dev/null 2>&1 || true
helm repo update

VPC_ID=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" --query "cluster.resourcesVpcConfig.vpcId" --output text)
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName="$CLUSTER_NAME" \
  --set region="$REGION" \
  --set vpcId="$VPC_ID" \
  --set serviceAccount.create=false \
  --set serviceAccount.name="$ALB_SA" ${HELM_CHART_VERSION:+--version "$HELM_CHART_VERSION"}

kubectl -n kube-system rollout restart deploy/aws-load-balancer-controller

# Wait for controller and webhook to be Ready
kubectl -n kube-system rollout status deploy/aws-load-balancer-controller --timeout=5m
kubectl -n kube-system get endpoints aws-load-balancer-webhook-service | grep -q ':' || \
  (echo "ALB webhook endpoints not ready"; exit 1)

echo "EKS ready. Node groups: admin-ng, app-coord-ng, app-worker-ng"
