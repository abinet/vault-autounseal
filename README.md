Example of HashiCorp Vault installation with Auto-Unseal.

This example configures vault init container running a script to initialize Vault and store unsealing keys as GitLab Variable to specified Gitlab Project

Installation instructions:

Update values.yaml with Gitlab configuration.

```
kubectl create namespace vault
kubectl -n vault create configmap vault-init-config from-file=init.sh
kubectl -n vault create secret generic gitlab-secret generic --from-literal=token=<PUT-TOKEN-HERE>
helm repo add hashicorp https://helm.releases.hashicorp.com
helm install vault hashicorp/vault --version 0.23.0 -f values.yaml
```