#!/usr/bin/env bats

load helper

setup() {
  current_context="$(kubectl config current-context)"
  # Create a temporary namespace for test
  namespace="test-kubernetes-resource-${RANDOM}"
  kubectl create ns "$namespace"
  # Create a kubeconfig file
  kubeconfig_file="$(mktemp)"
  kubectl config view --flatten --minify > "$kubeconfig_file"
  # Change the current-context to $namespace
  kubectl --kubeconfig "$kubeconfig_file" config set-context ${current_context} --namespace "$namespace"
  # Create a kubeconfig json without users (no token)
  kubeconfig_file_no_token="$(mktemp)"
  kubectl config view --flatten --minify -o json | jq -r 'del(.contexts[0].context.user,.users)' > "$kubeconfig_file_no_token"
  # create rolebinding for full namespace access to default service account in namespace to avoid forbidden errors with token
  kubectl create -n $namespace rolebinding --clusterrole=cluster-admin --serviceaccount=$namespace:default testaccount
  # get default service account
  serviceaccount=$(kubectl get -n $namespace serviceaccount default -o json | jq -r '.secrets[0].name')
  # Extract server from service account for testing
  server="$(kubectl get -n $namespace secret "$serviceaccount" -o json | jq -r '.data["server"]' | base64 -d)"
  # Extract token from service account for testing
  token="$(kubectl get -n $namespace secret "$serviceaccount" -o json | jq -r '.data["token"]' | base64 -d)"
}

teardown() {
  # Delete a temporary namespace
  kubectl delete ns "$namespace"
  # Remove a temporary kueconfig file
  rm "$kubeconfig_file"
}

@test "with outputs.use_aws_iam_authenticator" {
  run assets/out <<< "$(jq -n '{"source": {"use_aws_iam_authenticator": true, "aws_eks_cluster_name": "eks-cluster01", "server": $server, "token": $token}, "params": {"kubectl": "get po"}}' \
    --arg server "$server" \
    --arg token "$token")"
  assert_not_match 'did not find expected key' "$output"
}

@test "with outputs.aws_eks_assume_role" {
  run assets/out <<< "$(jq -n '{"source": {"use_aws_iam_authenticator": true, "aws_eks_cluster_name": "eks-cluster01", "aws_eks_assume_role": "arn:role", "server": $server, "token": $token}, "params": {"kubectl": "get po"}}' \
    --arg server "$server" \
    --arg token "$token")"
  assert_not_match 'did not find expected key' "$output"
}

@test "with source.kubeconfig" {
  run assets/out <<< "$(jq -n '{"source": {"kubeconfig": $kubeconfig}, "params": {"kubectl": $kubectl}}' \
    --arg kubeconfig "$(cat "$kubeconfig_file")" \
    --arg kubectl "run nginx --image nginx")"
  assert_match 'deployment.apps/nginx created' "$output"
  assert_success
}

@test "with source.context" {
  run assets/out <<< "$(jq -n '{"source": {"kubeconfig": $kubeconfig, "context": $context}, "params": {"kubectl": $kubectl}}' \
    --arg kubeconfig "$(cat "$kubeconfig_file")" \
    --arg kubectl "get po nginx" \
    --arg context "missing")"
  assert_match 'error: no context exists with the name: "missing"' "$output"
  assert_failure
}

@test "with outputs.kubeconfig_file" {
  run assets/out <<< "$(jq -n '{"source": {}, "params": {"kubectl": $kubectl, "kubeconfig_file": $kubeconfig_file}}' \
    --arg kubeconfig_file "$kubeconfig_file" \
    --arg kubectl "get ns kube-system -o name")"
  assert_match "namespace/kube-system" "$output"
  assert_success
}

@test "with outputs.namespace" {
  run kubectl --kubeconfig "$kubeconfig_file" run nginx --image=nginx
  assert_success

  run assets/out <<< "$(jq -n '{"source": {}, "params": {"kubectl": $kubectl, "kubeconfig_file": $kubeconfig_file, "namespace": $namespace}}' \
    --arg kubeconfig_file "$kubeconfig_file" \
    --arg kubectl "get po nginx" \
    --arg namespace "kube-system")"
  assert_failure
}

@test "with no credentials in outputs.kubeconfig_file and source.token" {
  run assets/out <<< "$(jq -n '{"source": {"token": $token}, "params": {"kubectl": $kubectl, "kubeconfig_file": $kubeconfig_file, "namespace": $namespace}}' \
    --arg token "$token" \
    --arg kubeconfig_file "$kubeconfig_file_no_token" \
    --arg kubectl "get ns $namespace -o name" \
    --arg namespace "$namespace")"
  assert_match "namespace/$namespace" "$output"
  assert_success
}

@test "command substitution in outputs.kubectl" {
  run kubectl --kubeconfig "$kubeconfig_file" run nginx --image=nginx
  assert_success

  run assets/out <<< "$(jq -n '{"source": {"kubeconfig": $kubeconfig}, "params": {"kubectl": $kubectl}}' \
    --arg kubeconfig "$(cat "$kubeconfig_file")" \
    --arg kubectl "patch deploy nginx -p '{\"spec\":{\"template\":{\"metadata\":{\"labels\":{\"updated_at\":\"'\$(date +%s)'\"}}}}}'")"
  assert_match 'deployment.extensions/nginx patched' "$output"
  assert_success

  run kubectl --kubeconfig "$kubeconfig_file" get deploy nginx -o go-template --template "{{.spec.template.metadata.labels.updated_at}}"
  assert_not_equal "<no value>" "${lines[0]}"
  assert_success
}

@test "pending pod" {
  # Request large resources, so that pod will fall into Pending state
  run assets/out <<< "$(jq -n '{"source": {"kubeconfig": $kubeconfig}, "params": {"kubectl": $kubectl}}' \
    --arg kubeconfig "$(cat "$kubeconfig_file")" \
    --arg kubectl "run nginx --image nginx --requests='cpu=1000'")"
  assert_match 'deployment.apps/nginx created' "$output"
  assert_failure
}
