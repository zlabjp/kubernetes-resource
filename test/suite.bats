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
}

teardown() {
  # Delete a temporary namespace
  kubectl delete ns "$namespace"
  # Remove a temporary kueconfig file
  rm "$kubeconfig_file"
}

@test "with source.kubeconfig" {
  run assets/out <<< "$(jq -n '{"source": {"kubeconfig": $kubeconfig}, "params": {"kubectl": $kubectl}}' \
    --arg kubeconfig "$(cat "$kubeconfig_file")" \
    --arg kubectl "run nginx --image nginx")"
  assert_match 'deployment.apps "nginx" created' "$output"
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

@test "command substitution in outputs.kubectl" {
  run kubectl --kubeconfig "$kubeconfig_file" run nginx --image=nginx
  assert_success

  run assets/out <<< "$(jq -n '{"source": {"kubeconfig": $kubeconfig}, "params": {"kubectl": $kubectl}}' \
    --arg kubeconfig "$(cat "$kubeconfig_file")" \
    --arg kubectl "patch deploy nginx -p '{\"spec\":{\"template\":{\"metadata\":{\"labels\":{\"updated_at\":\"'\$(date +%s)'\"}}}}}'")"
  assert_match 'deployment.extensions "nginx" patched' "$output"
  assert_success

  run kubectl --kubeconfig "$kubeconfig_file" get deploy nginx -o go-template --template "{{.spec.template.metadata.labels.updated_at}}"
  assert_not_equal "<no value>" "${lines[0]}"
  assert_success
}
