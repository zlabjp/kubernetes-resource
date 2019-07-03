#!/usr/bin/env bash

set -e -o pipefail; [[ -n "$DEBUG" ]] && set -x

AWS_IAM_AUTHENTICATOR_VERSION="$1"
if [[ -z "$AWS_IAM_AUTHENTICATOR_VERSION" ]]; then
    echo "Usage: $0 <version>" >&2
    exit 1
fi

sed -i -e "s/^ARG AWS_IAM_AUTHENTICATOR_VERSION=v[0-9\.]*$/ARG AWS_IAM_AUTHENTICATOR_VERSION=$AWS_IAM_AUTHENTICATOR_VERSION/" Dockerfile
sed -i -e "s/aws-iam-authenticator@v[0-9\.]*/aws-iam-authenticator@${AWS_IAM_AUTHENTICATOR_VERSION}/" README.md
