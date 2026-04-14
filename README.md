## 📦 Ingress Controller + Metrics Server Setup (README)

---

## ✅ Compatibility

* Works on:

  * kubeadm cluster ✅
  * kind cluster ✅
* ⚠️ Notes:

  * Kind manifest is optimized for kind (node labels, networking)
  * For kubeadm → small patch needed (given below)

---

# 🚀 Install Ingress Controller

## 1. Apply Ingress Manifest

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/kind/deploy.yaml
```

---

## 2. Wait for Controller

```bash
kubectl wait --namespace ingress-nginx \
--for=condition=ready pod \
--selector=app.kubernetes.io/component=controller \
--timeout=120s
```

---

## 3. Fix (ONLY if stuck in Pending — kubeadm case)

```bash
kubectl patch deployment ingress-nginx-controller -n ingress-nginx --type=json \
-p='[{"op": "remove", "path": "/spec/template/spec/nodeSelector"}]'
```

---

## 4. Verify

```bash
kubectl get pods -n ingress-nginx
```

---

# 📊 Install Metrics Server

## 1. Apply Metrics Server

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

---

## 2. Edit Deployment

```bash
kubectl -n kube-system edit deployment metrics-server
```

### Add inside `containers.args`:

```yaml
- --kubelet-insecure-tls
- --kubelet-preferred-address-types=InternalIP,Hostname,ExternalIP
```

---

## 3. Restart Deployment

```bash
kubectl -n kube-system rollout restart deployment metrics-server
```

---

## 4. Verify

```bash
kubectl get pods -n kube-system
kubectl top nodes
```

---

# ⚠️ Important Notes (kubeadm vs kind)

## For kubeadm:

* Must open ports:

  * NodePort / LoadBalancer access (depends on setup)
* Ensure:

  * kubelet certificate is reachable
  * cluster networking (CNI) is working

## For kind:

* Works out of the box
* Metrics server needs TLS bypass (already added above)

---

# ✅ Final Check

```bash
kubectl get pods -A
kubectl top nodes
kubectl get ingress
```
