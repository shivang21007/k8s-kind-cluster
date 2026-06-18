# Kubeadm Cluster Setup Runbook (Ubuntu + containerd + Calico)

This guide is built from a real setup flow: your command history, the kubeadm pattern from the blog you followed, and the Calico/Kubernetes port requirements that surfaced during debugging. Your history shows the exact sequence you used for kernel modules, sysctl, containerd, crictl, kubeadm, Calico, metrics-server, and troubleshooting, including the later cleanup and reboot cycle.

## 1) What this guide assumes

* Ubuntu nodes (one control plane, one or more workers)
* containerd as the runtime
* kubeadm / kubelet / kubectl installed from the Kubernetes package repository
* Calico as the CNI plugin
* AWS-style cloud networking, where Security Group rules matter a lot
* Kubernetes version `v1.35.0`
* Read this doc to open the following ports on master and worker node - [https://kubernetes.io/docs/reference/networking/ports-and-protocols/](https://kubernetes.io/docs/reference/networking/ports-and-protocols/)
* I have followed this guide to setup everything (original Doc) - [https://devopscube.com/setup-kubernetes-cluster-kubeadm/](https://devopscube.com/setup-kubernetes-cluster-kubeadm/)

The kubeadm flow itself is standard: kubeadm bootstraps the control plane, but it does not install a pod network, so the cluster is not truly usable until CNI is installed. The blog you followed says the same, and the Kubernetes docs also separate the core Kubernetes ports from CNI-specific ports. ([devopscube.com](https://devopscube.com/setup-kubernetes-cluster-kubeadm/?utm_source=chatgpt.com))

---

## 2) The mental model first

A kubeadm cluster has five layers that must all line up:

1. **OS readiness**: swap off, kernel modules loaded, forwarding enabled.
2. **Runtime readiness**: containerd running and speaking CRI.
3. **Kubernetes binaries**: kubelet, kubeadm, kubectl all at compatible versions.
4. **Control plane bootstrap**: `kubeadm init` creates certificates, static pod manifests, kubeconfig, and bootstrap token.
5. **Networking**: Calico creates pod-to-pod connectivity. Without this, nodes can be Ready or NotReady depending on what is broken, and pods can stay in `ContainerCreating`.

The biggest lesson from your journey is this: **Kubernetes can be installed correctly while the cluster still does not work** if CNI traffic is blocked. Calico needs node-to-node connectivity beyond the default Kubernetes component ports. Calico’s requirements document explicitly lists BGP TCP 179, VXLAN UDP 4789, and Typha TCP 5473 when those features are used. ([docs.tigera.io](https://docs.tigera.io/calico/latest/getting-started/kubernetes/requirements?utm_source=chatgpt.com))

---

## 3) Base OS preparation on every node

Run these on **all nodes**.

### 3.1 Update the machine

```bash
sudo apt update
sudo apt upgrade -y
```

### 3.2 Load kernel modules

```bash
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter
```

### 3.3 Enable required sysctl values

```bash
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF

sudo sysctl --system
```

### 3.4 Disable swap

```bash
sudo swapoff -a
```

To make it persistent after reboot, remove or comment swap entries in `/etc/fstab`.

### 3.5 Verify the base settings

```bash
swapon --show
lsmod | grep -E 'overlay|br_netfilter'
sysctl net.bridge.bridge-nf-call-iptables
sysctl net.bridge.bridge-nf-call-ip6tables
sysctl net.ipv4.ip_forward
```

Expected:

* `swapon --show` returns nothing
* both modules are loaded
* all sysctl values are `1`

Your command history shows this exact prep sequence, including module loading, sysctl config, and swapoff. 

---

## 4) Install and configure containerd on every node

### 4.1 Install containerd

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y containerd.io
```

### 4.2 Generate config and enable systemd cgroups

```bash
sudo containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
sudo systemctl enable --now containerd
sudo systemctl restart containerd
```

### 4.3 Verify runtime health

```bash
systemctl status containerd --no-pager
sudo crictl info | head
```

The `SystemdCgroup = true` setting is the right match for modern kubelet/systemd setups; your history shows you set that explicitly. 

---

## 5) Install crictl on every node

### 5.1 Pick a version

Your history settled on:

```bash
CRICTL_VERSION="v1.30.0"
```

### 5.2 Install

```bash
curl -fLO https://github.com/kubernetes-sigs/cri-tools/releases/download/${CRICTL_VERSION}/crictl-${CRICTL_VERSION}-linux-amd64.tar.gz
sudo tar zxvf crictl-${CRICTL_VERSION}-linux-amd64.tar.gz -C /usr/local/bin
rm -f crictl-${CRICTL_VERSION}-linux-amd64.tar.gz
```

### 5.3 Configure it for containerd

```bash
cat <<EOF | sudo tee /etc/crictl.yaml
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
EOF
```

### 5.4 Verify

```bash
crictl ps -a
```

Your history shows the first broken download happened because the version variable was not set; the fixed version was `v1.30.0`, and you switched to `curl -fLO` to fail properly on bad downloads. 

---

## 6) Install kubeadm, kubelet, and kubectl

### 6.1 Add the Kubernetes repository

Use the stable v1.35 repo:

```bash
KUBERNETES_VERSION=v1.35
curl -fsSL https://pkgs.k8s.io/core:/stable:/$KUBERNETES_VERSION/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/$KUBERNETES_VERSION/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update -y
```

### 6.2 Install matching versions

```bash
KUBERNETES_INSTALL_VERSION="1.35.0-1.1"
sudo apt-get install -y kubelet="$KUBERNETES_INSTALL_VERSION" kubectl="$KUBERNETES_INSTALL_VERSION" kubeadm="$KUBERNETES_INSTALL_VERSION"
sudo apt-mark hold kubelet kubeadm kubectl
```

### 6.3 Verify versions

```bash
kubeadm version -o short
kubelet --version
kubectl version --client
```

Your history confirms both `kubeadm` and `kubelet` were on `v1.35.0`, which is the cleanest state for a fresh build.

---

## 7) Bind kubelet to the correct node IP

This matters a lot on cloud VMs, because interfaces are often named `ens5`, `ens3`, etc., not `eth0`.

### 7.1 Get the primary private IP

```bash
local_ip="$(ip route get 1.1.1.1 | awk '{print $7}')"
```

This is better than hardcoding interface names because it asks the kernel which source IP it would actually use for outbound traffic.

### 7.2 Write kubelet defaults

```bash
cat <<EOF | sudo tee /etc/default/kubelet > /dev/null
KUBELET_EXTRA_ARGS=--node-ip=$local_ip
EOF
```

### 7.3 Verify

```bash
cat /etc/default/kubelet
```

Your history shows the move from an interface-based command to `ip route get 1.1.1.1`, and then the fix for permission issues using `sudo tee`.

---

## 8) Prepare the kubeadm config file

This is where the control plane identity and access path are defined.

### 8.1 Understand the two important IPs

* ``: the private IP the API server binds to inside the node.
* ``: the address clients and joining nodes use to reach the API server.

The blog you followed discusses the same distinction for private-IP-only control planes versus public-IP cloud control planes. ([devopscube.com](https://devopscube.com/setup-kubernetes-cluster-kubeadm/?utm_source=chatgpt.com))

### 8.2 Recommended layout for your setup

Use:

* `advertiseAddress`: the control-plane private IP
* `controlPlaneEndpoint`: the public IP plus `:6443`

Example:

```yaml
apiVersion: kubeadm.k8s.io/v1beta4
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: "192.168.x.x"
  bindPort: 6443
nodeRegistration:
  name: "controlplane"

---
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
kubernetesVersion: "v1.35.0"
controlPlaneEndpoint: "65.0.168.116:6443"
apiServer:
  extraArgs:
    - name: "enable-admission-plugins"
      value: "NodeRestriction"
    - name: "audit-log-path"
      value: "/var/log/kubernetes/audit.log"
controllerManager:
  extraArgs:
    - name: "node-cidr-mask-size"
      value: "24"
scheduler:
  extraArgs:
    - name: "leader-elect"
      value: "true"
networking:
  podSubnet: "10.244.0.0/16"
  serviceSubnet: "10.96.0.0/12"
  dnsDomain: "cluster.local"

---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: "systemd"
syncFrequency: "1m"

---
apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: KubeProxyConfiguration
mode: "ipvs"
conntrack:
  maxPerCore: 32768
  min: 131072
  tcpCloseWaitTimeout: "1h"
  tcpEstablishedTimeout: "24h"
```

### 8.3 Why `podSubnet` matters

Whatever CNI you install must match this CIDR. For Calico VXLAN setups, keeping `10.244.0.0/16` is common and aligns with your controller-manager cluster CIDR inspection.

Your history shows you checked the controller-manager `--cluster-cidr=10.244.0.0/16` before editing `custom-resources.yaml`.

---

## 9) Initialize the control plane

Run this on the control-plane node only:

```bash
sudo kubeadm init --config kubeadm.config
```

If you see `user is not running as root`, run it again with `sudo`. Your history shows that exact preflight failure and the successful rerun with root privileges. 

### 9.1 Expected output highlights

You should see:

* certificate generation
* static pod manifests for etcd, kube-apiserver, controller-manager, scheduler
* a bootstrap token
* the join command for workers

### 9.2 Copy kubeconfig for your user

```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

### 9.3 Verify

```bash
kubectl get nodes
kubectl get pods -A
```

At this stage, before CNI, the control plane is usually not fully Ready yet.

The Kubernetes docs also emphasize that kubeadm init does not finish the whole networking story; a pod network must be installed afterward. ([devopscube.com](https://devopscube.com/setup-kubernetes-cluster-kubeadm/?utm_source=chatgpt.com))

---

## 10) Install Calico the right way

Your real debugging showed that CNI was the hardest part, and that the cloud firewall was blocking Calico control and data-plane traffic until the relevant ports were opened.

### 10.1 Install the Calico operator CRDs

```bash
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.31.3/manifests/operator-crds.yaml
```

### 10.2 Install the Tigera operator

```bash
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.31.3/manifests/tigera-operator.yaml
```

### 10.3 Download and edit the custom resources

```bash
curl -O https://raw.githubusercontent.com/projectcalico/calico/v3.31.3/manifests/custom-resources.yaml
```

Edit the IP pool so it matches your cluster pod CIDR:

```yaml
cidr: 10.244.0.0/16
```

Then apply:

```bash
kubectl apply -f custom-resources.yaml
```

### 10.4 What to expect while Calico starts

It is normal for Calico pods to be pending or initializing for a short time. Eventually:

* `calico-node` should become `Running`
* CoreDNS should move from `Pending` to `Running`
* nodes should become `Ready`

### 10.5 Why your cloud firewall mattered

Calico’s official docs list extra traffic that must be allowed depending on the networking mode:

* BGP: TCP 179
* VXLAN: UDP 4789
* Typha: TCP 5473

Kubernetes’ general ports doc does not replace these CNI-specific requirements. ([kubernetes.io](https://kubernetes.io/docs/reference/networking/ports-and-protocols/?utm_source=chatgpt.com))

---

## 11) Understand the ports you actually needed

This is the part your debugging made very clear:

### Kubernetes core control-plane ports

Examples include:

* 6443 for the API server
* 10250 for the kubelet API
* etcd ports on the control plane

Those are documented by Kubernetes. ([kubernetes.io](https://kubernetes.io/docs/reference/networking/ports-and-protocols/?utm_source=chatgpt.com))

### Calico-specific ports

Depending on your Calico config, the cluster also needs node-to-node traffic such as:

* TCP 179 for BGP
* UDP 4789 for VXLAN
* TCP 5473 for Typha

Your AWS security group had to allow that traffic between nodes, which is why Calico finally worked once those rules were opened. The Calico requirements docs explicitly describe these ports. ([docs.tigera.io](https://docs.tigera.io/calico/latest/getting-started/kubernetes/requirements?utm_source=chatgpt.com))

### Practical cloud rule

The simplest rule in AWS is often:

* allow all traffic **from the same node security group to itself**

That avoids chasing individual CNI ports one by one.

---

## 12) Install metrics-server

Once the cluster is stable, add metrics-server:

```bash
kubectl apply -f https://raw.githubusercontent.com/techiescamp/cka-certification-guide/refs/heads/main/lab-setup/manifests/metrics-server/metrics-server.yaml
```

Then verify:

```bash
kubectl get pods -n kube-system
kubectl top nodes
```

If `kubectl top nodes` says the Metrics API is not available, confirm the metrics-server pod is Running and that it can talk to kubelets. In many lab setups, the metrics-server manifest needs `--kubelet-insecure-tls` or similar trust settings depending on the environment.

Your history shows this exact `Metrics API not available` phase before the deployment settled. 

---

## 13) Smoke-test the cluster

Create a simple deployment and service:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
spec:
  selector:
    matchLabels:
      app: nginx
  replicas: 2
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        ports:
        - containerPort: 80
EOF

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
spec:
  selector:
    app: nginx
  type: NodePort
  ports:
    - port: 80
      targetPort: 80
      nodePort: 32000
EOF
```

Then verify:

```bash
kubectl get pods
kubectl get svc
```

This checks:

* scheduling works
* CNI works
* Service networking works
* NodePort plumbing works

Kubernetes Service docs describe NodePort as binding a port on every node and forwarding traffic to the Service backends. ([kubernetes.io](https://kubernetes.io/docs/concepts/services-networking/service/?utm_source=chatgpt.com))

---

## 14) DNS verification

Create a dnsutils pod or use a pod with `nslookup`.

Useful test:

```bash
kubectl exec -it dnsutils -- nslookup kubernetes.default
kubectl exec -it dnsutils -- nslookup google.com
```

Your experience showed CoreDNS also depended on the same cloud networking path; once the right ports were opened between worker nodes, DNS started working too. That is consistent with the idea that cluster DNS is only as healthy as pod networking.

---

## 15) When you must reset and start over

Sometimes the cleanest move is a full reset. Your history shows you ended up doing exactly that after Calico namespace cleanup issues and finalizer trouble.

### 15.1 Reset on every node

```bash
sudo kubeadm reset -f
sudo rm -rf /etc/cni/net.d/*
sudo rm -rf /var/lib/cni/*
sudo rm -rf /var/lib/kubelet/*
sudo rm -rf /etc/kubernetes/*
sudo iptables -F
sudo iptables -t nat -F
sudo iptables -t mangle -F
sudo iptables -X
sudo systemctl restart containerd
sudo systemctl restart kubelet
```

### 15.2 Reboot if needed

```bash
sudo reboot
```

### 15.3 Re-run the prerequisites checklist

* swap off
* containerd healthy
* kubelet healthy
* kernel modules loaded
* sysctl values correct
* node IP configured correctly

Your later history includes this exact reset/reboot/rebuild cycle, which is the right response when cluster state gets too tangled. 

---

## 16) Troubleshooting guide

### 16.1 `kubeadm init` says you are not root

Run:

```bash
sudo kubeadm init --config kubeadm.config
```

### 16.2 `Permission denied` writing to `/etc/default/kubelet`

Use `sudo tee`, not shell redirection alone.

### 16.3 `gzip: stdin: not in gzip format`

Your download URL or version variable is wrong. Re-check the file size and use `curl -fLO`.

### 16.4 Node stays `NotReady`

Usually one of:

* wrong `--node-ip`
* CNI not installed
* firewall blocking Calico traffic
* swap still enabled
* containerd or kubelet unhealthy

### 16.5 Calico `calico-node` stuck in `0/1`

Check:

* node-to-node traffic
* TCP 179
* TCP 5473
* UDP 4789 ( on all machines)
* Typha and BGP health

### 16.6 CoreDNS pods pending or DNS failing

Almost always a symptom of CNI problems, not CoreDNS itself.

---

## 17) The final sequence you should memorize

```text
1. Prepare OS
2. Install containerd
3. Install crictl
4. Install kubeadm/kubelet/kubectl
5. Set node IP
6. kubeadm init
7. copy kubeconfig
8. install Calico
9. open Calico traffic in cloud firewall
10. verify nodes Ready
11. join workers
12. install metrics-server
13. smoke-test with nginx and DNS
```

That is the whole game.

---

## 18) What your journey proved

The hard part was not kubeadm itself. It was the interaction between:

* kubeadm bootstrap
* Calico networking
* cloud security rules
* DNS and service traffic

That is the exact reason a kubeadm cluster can look “installed” yet still be unusable.

If you keep the control-plane IP choice, node IP choice, pod CIDR, and Calico ports aligned, the whole build becomes predictable.
