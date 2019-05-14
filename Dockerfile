FROM golang:1.10

RUN set -x && \
    go get -u -v github.com/kubernetes-sigs/aws-iam-authenticator/cmd/aws-iam-authenticator

FROM ubuntu:18.04

MAINTAINER Kazuki Suda <ksuda@zlab.co.jp>

ARG KUBERNETES_VERSION=

RUN set -x && \
    apt-get update && \
    apt-get install -y jq curl gettext-base && \
    [ -z "$KUBERNETES_VERSION" ] && KUBERNETES_VERSION=$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt) ||: && \
    curl -s -LO https://storage.googleapis.com/kubernetes-release/release/${KUBERNETES_VERSION}/bin/linux/amd64/kubectl && \
    chmod +x ./kubectl && \
    mv ./kubectl /usr/local/bin/kubectl && \
    kubectl version --client && \
    rm -rf /var/lib/apt/lists/*

COPY --from=0 /go/bin/aws-iam-authenticator /usr/local/bin/

RUN mkdir -p /opt/resource
COPY assets/* /opt/resource/
