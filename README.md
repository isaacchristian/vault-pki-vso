# Issue Native K8s Certs with Vault Secrets Operator 🚀

## Context 📖

I recently did the [Managing Kubernetes Native Secrets with the VSO](https://developer.hashicorp.com/vault/tutorials/kubernetes-introduction/vault-secrets-operator) tutorial and wanted to try it out with Vault's PKI Secrets Engine, issuing certs natively in k8s pods.

Some of the steps are similar, but the VaultPKISecret custom resource and spec are a bit different. Here are the steps I took to get this deployed and issuing certificates.

## Initial Setup 📝

Start a minikube cluster:

`minikube start`

If you don't already have the HashiCorp repo, run the following command:

`helm repo add hashicorp https://helm.releases.hashicorp.com`

Within this directory, apply the `vault-values.yaml` file to a `vault` namespace, using the most recent helm chart installation:

`helm install vault hashicorp/vault -n vault --create-namespace --values vault-values.yaml`

You should see the `vault-0` pod running:

`kubectl get pods -n vault`

## Configuring Vault 🔐

Connect to the `vault-0` instance:

`kubectl exec -it vault-0 -n vault -- /bin/sh`

Within your `vault-0` instance, upload the `pki_int.hcl` policy. You can do it a few ways, create a new file and upload, tee or vi. However you do it, write:

```
vault policy write pki_int pki_int.hcl
Success! Uploaded policy: pki_int
```

Configure the Kubernetes auth method:

```
vault auth enable -path demo-pki-mount kubernetes
Success! Enabled kubernetes auth method at: demo-pki-mount/

vault write auth/demo-pki-mount/config \
> kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443"
Success! Data written to: auth/demo-pki-mount/config

vault write auth/demo-pki-mount/role/role1 \
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
chmod +x enable_pki_engine.sh
./enable_pki_engine.sh
```

Then, exit the vault instance: `exit`

## Configuring VSO 🔄

Run:

`helm install vault-secrets-operator hashicorp/vault-secrets-operator -n vault-secrets-operator-system --create-namespace --values pki-vault-operator-values.yaml`

Create a namespace called **app** for your k8s cluster:

```
kubectl create ns app
namespace/app created
```

Apply the K8s auth method for the `secret-pki`:

```
kubectl apply -f vault-auth-pki.yaml
vaultauth.secrets.hashicorp.com/pki-auth created
```

Create the secret name for `secret-pki` in the **app** namespace:

```
kubectl apply -f pki-secret.yaml
vaultpkisecret.secrets.hashicorp.com/demo-pki-app created
```

## Configuring Transit Encryption


