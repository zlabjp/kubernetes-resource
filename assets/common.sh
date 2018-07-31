#!/usr/bin/env bash

# Copyright 2017, Z Lab Corporation. All rights reserved.
# Copyright 2017, kubernetes resource contributors
#
# For the full copyright and license information, please view the LICENSE
# file that was distributed with this source code.

# setup_kubectl prepares kubectl and exports the KUBECONFIG environment variable.
setup_kubectl() {
  local payload
  payload=$1

  KUBECONFIG="$(mktemp "$TMPDIR/kubernetes-resource-kubeconfig.XXXXXX")"
  export KUBECONFIG

  # Optional. The path of kubeconfig file
  local kubeconfig_file
  kubeconfig_file="$(jq -r '.params.kubeconfig_file // ""' < "$payload")"
  # Optional. The content of kubeconfig
  local kubeconfig
  kubeconfig="$(jq -r '.source.kubeconfig // ""' < "$payload")"

  if [[ -n "$kubeconfig_file"  ]]; then
    if [[ ! -f "$kubeconfig_file" ]]; then
      echoerr "kubeconfig file '$kubeconfig_file' does not exist"
      exit 1
    fi

    cat "$kubeconfig_file" > "$KUBECONFIG"
  elif [[ -n "$kubeconfig" ]]; then
    echo "$kubeconfig" > "$KUBECONFIG"
  else
    # Optional. The address and port of the API server. Requires token.
    local server
    server="$(jq -r '.source.server // ""' < "$payload")"
    # Optional. Bearer token for authentication to the API server. Requires server.
    local token
    token="$(jq -r '.source.token // ""' < "$payload")"
    # Optional. A certificate file for the certificate authority.
    local certificate_authority
    certificate_authority="$(jq -r '.source.certificate_authority // ""' < "$payload")"
    # Optional. If true, the API server's certificate will not be checked for
    # validity. This will make your HTTPS connections insecure. Defaults to false.
    local insecure_skip_tls_verify
    insecure_skip_tls_verify="$(jq -r '.source.insecure_skip_tls_verify // ""' < "$payload")"

    if [[ -z "$server" || -z "$token" ]]; then
      echoerr 'You must specify "server" and "token", if not specify "kubeconfig".'
      exit 1
    fi

    local -r AUTH_NAME=auth
    local -r CLUSTER_NAME=cluster
    local -r CONTEXT_NAME=kubernetes-resource

    # Build options for kubectl config set-credentials
    # Avoid to expose the token string by using placeholder
    local set_credentials_opts
    set_credentials_opts=("--token=**********")
    exe kubectl config set-credentials "$AUTH_NAME" "${set_credentials_opts[@]}"
    # placeholder is replaced with actual token string
    sed -i -e "s/[*]\\{10\\}/$token/" "$KUBECONFIG"

    # Build options for kubectl config set-cluster
    local set_cluster_opts
    set_cluster_opts=("--server=$server")
    if [[ -n "$certificate_authority" ]]; then
      local ca_file
      ca_file=$(mktemp "$TMPDIR/kubernetes-resource-ca_file.XXXXXX")
      echo -e "$certificate_authority" > "$ca_file"
      set_cluster_opts+=("--certificate-authority=$ca_file")
    fi
    if [[ "$insecure_skip_tls_verify" == "true" ]]; then
      set_cluster_opts+=("--insecure-skip-tls-verify")
    fi
    exe kubectl config set-cluster "$CLUSTER_NAME" "${set_cluster_opts[@]}"

    exe kubectl config set-context "$CONTEXT_NAME" --user="$AUTH_NAME" --cluster="$CLUSTER_NAME"

    exe kubectl config use-context "$CONTEXT_NAME"

    # Optional. Use the AWS EKS authenticator
    local use_aws_iam_authenticator
    use_aws_iam_authenticator="$(jq -r '.source.use_aws_iam_authenticator // ""' < "$payload")"
    local aws_eks_cluster_name
    aws_eks_cluster_name="$(jq -r '.source.aws_eks_cluster_name // ""' < "$payload")"
    if [[ "$use_aws_iam_authenticator" == "true" ]]; then
      if [ -z $aws_eks_cluster_name ]; then
        echoerr 'You must specify a clustername when using aws_iam_authenticator.'
        exit 1
      fi
      echo "    exec:
      apiVersion: client.authentication.k8s.io/v1alpha1
      args:
      - token
      - -i
      - ${aws_eks_cluster_name}
      command: aws-iam-authenticator
      env: null" >> $KUBECONFIG
    fi
  fi

  # Optional. The namespace scope. Defaults to default if doesn't specify in kubeconfig.
  local namespace
  namespace="$(jq -r '.params.namespace // ""' < "$payload")"
  if [[ -z "$namespace" ]]; then
    # Optional. The namespace scope. Defaults to `default`. If set along with `kubeconfig`, `namespace` will override the namespace in the current-context
    namespace="$(jq -r '.source.namespace // ""' < "$payload")"
  fi
  if [[ -n "$namespace" ]]; then
    exe kubectl config set-context "$(kubectl config current-context)" --namespace="$namespace"
  fi

  # Optional. The name of the kubeconfig context to use.
  local context
  context="$(jq -r '.source.context // ""' < "$payload")"
  if [[ -n "$context" ]]; then
    exe kubectl config use-context "$context"
  fi

  # Display the client and server version information
  exe kubectl version

  # Ignore the error from `kubectl cluster-info`. From v1.9.0, this command
  # fails if it cannot find the cluster services.
  # See https://github.com/kubernetes/kubernetes/commit/998f33272d90e4360053d64066b9722288a25aae
  exe kubectl cluster-info 2>/dev/null ||:
}

# current_namespace outputs the current namespace.
current_namespace() {
  local namespace

  namespace="$(kubectl config view -o "jsonpath={.contexts[?(@.name==\"$(kubectl config current-context)\")].context.namespace}")"
  [[ -z "$namespace" ]] && namespace=default
  echo $namespace
}

# current_cluster outputs the address and port of the API server.
current_cluster() {
  local cluster

  cluster="$(kubectl config view -o "jsonpath={.contexts[?(@.name==\"$(kubectl config current-context)\")].context.cluster}")"
  kubectl config view -o "jsonpath={.clusters[?(@.name==\"${cluster}\")].cluster.server}"
}

# wait_until_pods_ready waits for all pods to be ready in the current
# namespace, which are excluded terminating and failed/succeeded pods.
# $1: The number of seconds that waits until all pods are ready.
# $2: The interval (sec) on which to check whether all pods are ready.
# $3: A label selector to identify a set of pods which to check whether those are ready. Defaults to every pods in the namespace.
wait_until_pods_ready() {
  local period interval selector template

  period="$1"
  interval="$2"
  selector="$3"

  echo "Waiting for pods to be ready for ${period}s (interval: ${interval}s, selector: ${selector:-''})"

  # The list of "<pod-name> <ready(True|False)>" which is excluded terminating and failed/succeeded pods.
  template="$(cat <<EOL
{{- range .items -}}
{{- if and (not .metadata.deletionTimestamp) (ne .status.phase "Failed") (ne .status.phase "Succeeded") -}}
{{.metadata.name}}{{range .status.conditions}}{{if eq .type "Ready"}} {{.status}}{{end}}{{end}}{{"\\n"}}
{{- end -}}
{{- end -}}
EOL
)"

  local statuses not_ready ready
  for ((i=0; i<period; i+=interval)); do
    sleep "$interval"

    statuses="$(kubectl get po --selector="$selector" -o template --template="$template")"
    not_ready="$(echo "$statuses" | grep -c "False" ||:)"
    ready="$(echo "$statuses" | grep -c "True" ||:)"

    echo "Waiting for pods to be ready... ($ready/$((not_ready + ready)))"

    if [[ "$not_ready" -eq 0 ]]; then
      return 0
    fi
  done

  echo "Waited for ${period}s, but the following pods are not ready yet."
  echo "$statuses" | awk '{if ($2 == "False") print "- " $1}'
  return 1
}

# echoerr prints an error message in red color.
echoerr() {
  echo -e "\\e[01;31mERROR: $*\\e[0m"
}

# exe executes the command after printing the command trace to stdout
exe() {
  echo "+ $*"; "$@"
}

# on_exit prints the last error code if it isning  0.
on_exit() {
  local code

  code=$?
  [[ $code -ne 0 ]] && echo && echoerr "Failed with error code $code"
  return $code
}
# vim: ai ts=2 sw=2 et sts=2 ft=sh
