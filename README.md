# Issue Native K8s Certs with Vault Secrets Operator 🚀

## Context 📖

I recently did the [Managing Kubernetes Native Secrets with the VSO](https://developer.hashicorp.com/vault/tutorials/kubernetes-introduction/vault-secrets-operator) tutorial and wanted to try it out with Vault's PKI Secrets Engine, issuing certs natively in k8s pods.

Some of the steps are similar, but the VaultPKISecret custom resource and spec are a bit different. Here are the steps I took to get this deployed and issuing certificates.

## Initial Setup 📝

Start a minikube cluster:

`% minikube start`

If you don't already have the HashiCorp repo, run the following command:

`% helm repo add hashicorp https://helm.releases.hashicorp.com`

Within this directory, apply the `vault-values.yaml` file to a `vault` namespace, using the most recent helm chart installation:

`% helm install vault hashicorp/vault -n vault --create-namespace --values vault-values.yaml`

You should see the `vault-0` pod running:

`% kubectl get pods -n vault`

## Configuring Vault 🔐

Connect to the `vault-0` instance:

`% kubectl exec -it vault-0 -n vault -- /bin/sh`

Within your `vault-0` instance, upload the `pki_int.hcl` policy. You can do it a few ways, create a new file and upload, tee or vi. However you do it, write:

```
$ vault policy write pki_int pki_int.hcl
Success! Uploaded policy: pki_int
```

Configure the Kubernetes auth method:

```
$ vault auth enable -path demo-pki-mount kubernetes
Success! Enabled kubernetes auth method at: demo-pki-mount/

$ vault write auth/demo-pki-mount/config \
> kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443"
Success! Data written to: auth/demo-pki-mount/config

$ vault write auth/demo-pki-mount/role/role1 \
> bound_service_account_names=demo-pki-app \
> bound_service_account_namespaces=app \
> policies=pki_int \
> audience=vault \
> ttl=24h

 Success! Data written to: auth/demo-pki-mount/role/role1
```

Enable a PKI & PKI Intermediate Secrets Engine:

For the `enable_pki_engine.sh` script, change the paths within to paths you'll remember as they will be where your certificates are saved. Run:

```
$ chmod +x enable_pki_engine.sh
$ ./enable_pki_engine.sh
```

Then, exit the vault instance: `exit`

## Configuring VSO 🔄

Run:

`% helm install vault-secrets-operator hashicorp/vault-secrets-operator -n vault-secrets-operator-system --create-namespace --values pki-vault-operator-values.yaml`

Create a namespace called **app** for your k8s cluster:

```
% kubectl create ns app
namespace/app created
```

Apply the K8s auth method for the `secret-pki`:

```
% kubectl apply -f vault-auth-pki.yaml
vaultauth.secrets.hashicorp.com/pki-auth created
```

Create the secret name for `secret-pki` in the **app** namespace:

```
% kubectl apply -f pki-secret.yaml
vaultpkisecret.secrets.hashicorp.com/demo-pki-app created
```

## Configuring Transit Encryption 🚊

This is crucial for renewing leases for PKI without fetching new client tokens, if ever your VSO were to restart. With the transit secrets engine, your client token cache is encrypted both in-transit and at-rest. When you installed the VSO with the `pki-vault-operator-values`, you already set up the VSO for client token cache. So you kinda have to do this step or else you'll get some errors. 

Connect back into the vault instance:

```
% kubectl exec -it vault-0 -n vault -- /bin/sh

$ vault policy write demo-auth-policy-operator demo-auth-policy-operator.hcl
Success! Uploaded policy: demo-auth-policy-operator

$ vault secrets enable -path=demo-transit transit
Success! Enabled the transit secrets engine at: demo-transit/

$ vault write -force demo-transit/keys/vso-client-cache
Success! Data written to: demo-transit/keys/vso-client-cache

$ vault write auth/demo-auth-mount/role/auth-role-operator \
> bound_service_account_names=vault-secrets-operator-controller-manager \
> bound_service_account_namespaces=vault-secrets-operator-system \
> token_ttl=0 \
> token_period=120 \
> token_policies=demo-auth-policy-operator \
> audience=vault
Success! Data written to: auth/demo-auth-mount/role/auth-role-operator
```

## Confirming Issued Certificates 📄

A few ways, you can use `k9s` which is definitely a fun graphic way to scope around your cluster (as graphic as you can get in the terminal). Or if you haven't installed it yet, you can run these commands to ensure you have your issued certs within your **app** namespace:

```
% kubectl get secrets -n app
NAME         TYPE     DATA   AGE
secret-pki   Opaque   8      9m

% kubectl describe secret secret-pki -n app
Name:         secret-pki
Namespace:    app
Labels:       app.kubernetes.io/component=secret-sync
              app.kubernetes.io/managed-by=hashicorp-vso
              app.kubernetes.io/name=vault-secrets-operator
              secrets.hashicorp.com/vso-ownerRefUID=cc743c5c-8431-4ef4-8e4d-84fc1ec1763d
Annotations:  <none>

Type:  Opaque

Data
====
expiration:        10 bytes
issuing_ca:        1435 bytes
private_key:       1674 bytes
private_key_type:  3 bytes
serial_number:     59 bytes
_raw:              6058 bytes
ca_chain:          1435 bytes
certificate:       1228 bytes
```

## Heads up! ⚠️

**Don't** try logging in with Vault and K8s! You solved this with the transit secrets engine and enabling client token caching. If you use the JWT, for example, you'll throw it off and end up having to re-enable your auth methods.

## References 🔥

1. [Manage Kubernetes Native Secrets with the Vault Secrets Operator](https://developer.hashicorp.com/vault/tutorials/kubernetes-introduction/vault-secrets-operator)
2. [VaultPKISecret Custom Resource](https://developer.hashicorp.com/vault/docs/deploy/kubernetes/vso/sources/vault#vaultpkisecret-custom-resource)
3. [VaultPKISecret](https://developer.hashicorp.com/vault/docs/deploy/kubernetes/vso/api-reference#vaultpkisecret)
4. [VaultPKISecretList](https://developer.hashicorp.com/vault/docs/deploy/kubernetes/vso/api-reference#vaultpkisecretlist)
5. [VaultPKISecretSpec](https://developer.hashicorp.com/vault/docs/deploy/kubernetes/vso/api-reference#vaultpkisecretspec)

