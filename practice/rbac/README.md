# Kubernetes User Auth via Certificates + RBAC

This guide shows how to:

* Create user private key + CSR
* Submit CSR to Kubernetes
* Approve and extract certificate
* Create Role & RoleBinding
* Configure kubeconfig (credentials + context)
* Use the new user

## resources :
- https://kubernetes.io/docs/tasks/tls/certificate-issue-client-csr/
- https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/
---

## 1. Generate Key & CSR

```bash
# Generate private key
openssl genrsa -out adam.key 3072

# Generate CSR (CN = username)
openssl req -new -key adam.key -out adam.csr -subj "/CN=adam"
```

---

## 2. Create Kubernetes CSR Object

Convert CSR to base64:

```bash
cat adam.csr | base64 | tr -d "\n"
```

Create CSR resource:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: adam
spec:
  request: <BASE64_CSR>
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 86400
  usages:
  - client auth
EOF
```

---

## 3. Approve CSR & Get Certificate

```bash
# Approve CSR
kubectl certificate approve adam

# Extract certificate
kubectl get csr adam -o jsonpath='{.status.certificate}' | base64 -d > adam.crt
```

---

## 4. Create Role

```bash
kubectl create role pod-reader \
  --verb=get --verb=watch --verb=list \
  --resource=pods \
  -o yaml > role.yml
```

Apply:

```bash
kubectl apply -f role.yml
```

---

## 5. Create RoleBinding

```bash
kubectl create rolebinding pod-reader-binding \
  --user=adam \
  --role=pod-reader \
  -o yaml > rolebinding.yml
```

Apply:

```bash
kubectl apply -f rolebinding.yml
```

---

## 6. Configure User Credentials (kubeconfig)

```bash
kubectl config set-credentials adam \
  --client-key=adam.key \
  --client-certificate=adam.crt \
  --embed-certs=true
```

---

## 7. Create Context

```bash
kubectl config set-context adam \
  --cluster=kind-sg \
  --user=adam
```

---

## 8. Switch Context

```bash
kubectl config use-context adam
```

---

## 9. Verify Access

```bash
kubectl auth whoami

kubectl auth can-i get pods
kubectl auth can-i delete pods
```

---

## 10. Quick Debug Tips

```bash
kubectl get csr
kubectl get role
kubectl get rolebinding
kubectl config get-contexts
```

---

## ⚡ Key Concepts (First Principles)

* **Private Key (`.key`)** → proves identity
* **CSR (`.csr`)** → request to cluster CA
* **Certificate (`.crt`)** → signed identity
* **Role** → what actions are allowed
* **RoleBinding** → who gets those permissions
* **Context** → (cluster + user + namespace)

---

## 🔁 Flow Summary

```text
key → csr → k8s csr → approve → crt
         ↓
   kubeconfig user
         ↓
 role + rolebinding
         ↓
     context
         ↓
      access
```

---

## 🧪 Example Test

```bash
kubectl get pods
```

✔️ Should work if RBAC is correct
❌ Should fail if permission not granted

---
