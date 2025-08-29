#!/bin/bash

set -euxo pipefail

vault secrets enable pki
vault secrets tune -max-lease-ttl=87600h pki
vault write -field=certificate pki/root/generate/internal \
   common_name="Vault Root CA" \
   issuer_name="vault-root-ca" \
   ttl=87600h > /absolute/path/to/root_ca.crt
vault write pki/config/cluster \
   path=http://127.0.0.1:8200//v1/pki \
   aia_path=http://127.0.0.1:8200//v1/pki
vault write pki/roles/root \
   allowed_subdomains="vault.internal" \
   allow_subdomains=true \
   allow_ip_sans=true \
   allow_any_name=false \
   no_store=false
vault policy write pki -<<EOF
path "pki/*" {
	capabilities = ["create", "read", "update", "list"]
}
EOF
vault write pki/config/urls \
   issuing_certificates={{cluster_aia_path}}/issuer/{{issuer_id}}/der \
   crl_distribution_points={{cluster_aia_path}}/issuer/{{issuer_id}}/crl/der \
   ocsp_servers={{cluster_path}}/ocsp \
   enable_templating=true
vault secrets enable -path=pki_int pki
vault secrets tune -max-lease-ttl=43800h pki_int
vault write -format=json pki_int/intermediate/generate/internal \
   common_name="Vault Intermediate CA" \
   issuer_name="vault-int-ca" \
   | jq -r '.data.csr' > /absolute/path/to/pki_intermediate.csr
vault write -format=json pki/root/sign-intermediate \
   issuer_ref="vault-root-ca" \
   csr=@pki_intermediate.csr \
   format=pem_bundle ttl="43800h" \
   | jq -r '.data.certificate' > /absolute/path/to/intermediate.cert.pem
vault write pki_int/intermediate/set-signed certificate=@intermediate.cert.pem
vault write pki_int/config/cluster \
   path=http://127.0.0.1:8200//v1/pki_int \
   aia_path=http://127.0.0.1:8200//v1/pki_int
vault write pki_int/roles/machines \
   issuer_ref="$(vault read -field=default pki_int/config/issuers)" \
   allowed_domains="vault.internal" \
   allow_subdomains=true \
   allow_ip_sans=true \
   allow_any_name=false \
   max_ttl="720h" \
   no_store=false
vault write pki_int/config/urls \
   issuing_certificates={{cluster_aia_path}}/issuer/{{issuer_id}}/der \
   crl_distribution_points={{cluster_aia_path}}/issuer/{{issuer_id}}/crl/der \
   ocsp_servers={{cluster_path}}/ocsp \
   enable_templating=true
