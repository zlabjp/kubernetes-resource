# kubernetes-resource

A Concourse resource for controlling the Kubernetes cluster.

## Source Configuration

### kubeconfig

- `kubeconfig`: *Optional.* A kubeconfig file.
    ```yaml
    kubeconfig: |
      apiVersion: v1
      clusters:
      - cluster:
        ...
    ```

### cluster configs

- `server`: *Optional.* The address and port of the API server. Requires `token`.
- `token`: *Required.* Bearer token for authentication to the API server. Requires `server`.
- `namespace`: *Optional.* The namespace scope. Defaults to `default` if doesn't specify in `kubeconfig`.
- `certificate_authority`: *Optional.* A certificate file for the certificate authority.
    ```yaml
    certificate_authority: |
        -----BEGIN CERTIFICATE-----
        ...
        -----END CERTIFICATE-----
    ```
- `insecure_skip_tls_verify`: `Optional.` If true, the API server's certificate will not be checked for validity. This will make your HTTPS connections insecure. Defaults to `false`.

## Behavior

### `check`: Do nothing.

### `in`: Do nothing.

### `out`: Control the Kubernetes cluster.

Control the Kubernetes cluster like `kubectl apply`, `kubectl delete`, `kubectl label` and so on.

#### Parameters

- `kubectl`: *Required.* Specify the operation that you want to perform on one or more resources, for example `apply`, `delete`, `label`.
- `wait_until_ready`: *Optional.* The number of seconds that waits until all pods are ready. 0 means don't wait. Defaults to `30`.
- `wait_until_ready_interval`: *Optional.* The interval (sec) on which to check whether all pods are ready. Defaults to `3`.

## Example

```yaml
resource_types:
- name: kubernetes
  type: docker-image
  source:
    repository: zlabjp/kubernetes-resource:1.7

resources:
- name: kubernetes-production
  type: kubernetes
  source:
    server: https://192.168.99.100:8443
    namespace: production
    token: {{kubernetes-production-token}}
    certificate_authority: {{kubernetes-production-cert}}
- name: my-app
  type: git
  source:
    ...

jobs:
- name: kubernetes-deploy-production
  plan:
  - get: my-app
    trigger: true
  - put: kubernetes-production
    params:
      kubectl: apply -f my-app/k8s -f my-app/k8s/production
```
