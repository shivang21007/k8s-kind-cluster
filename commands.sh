#!/bin/bash
#-----------------------
#Everything in Kubernetes is a manifest file.

#-----------------------

kind create cluster --config ./kind-config.yaml --name sg-cluster # create a cluster

kubectl get nodes # get all nodes

kubectl cluster-info --context kind-sg-cluster # get cluster info

kubectl config get-contexts # get all contexts

kubectl config set-context --current --namespace=default # set default namespace

kubectl get ns # get all namespaces

kubectl apply -f ns/namespace.yml # create a custom namespace

kubectl get pods # get all pods in default namespace

kubectl apply -f pods/pod.yml # create a pod in default namespace

kubectl get pods -n nginx-ns # get all pods in nginx-ns namespace

kubectl delete pod nginx-pod -n nginx-ns # delete a pod in nginx-ns namespace

kubectl delete -f ns/namespace.yml # delete a same namespace

kubectl apply -f deployments/deployments.yml --dry-run=client

kubectl apply -f deployments/deployments.yml 

kubectl scale deployment nginx-deployment -n nginx-ns --replicas=5

kudectl apply -f services/service.yml

kubectl get svc -n nginx-ns

sudo -E kubectl port-forward svc/nginx-svc -n nginx-ns 82:82 --address=0.0.0.0

curl localhost:8282

kubectl get all -n nginx-ns

kubectl scale deployment nginx-deployment -n nginx-ns --replicas=0

kubectl exec -it nginx-deployment-694b6bbcfd-vbdvb -n nginx-ns -- /bin/bash #to enter into the pod e.g. nginx-deployment-694b6bbcfd-vbdvb

kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
# install/deploy ingress controller plugin

kubectl get pods -n ingress-nginx # get all pods in ingress-nginx namespace

kubectl get svc -n ingress-nginx # get all services in ingress-nginx namespace

kubectl apply -f ingress/*

kuectl get ing -A

sudo -E kubectl port-forward svc/ingress-nginx-controller -n ingress-nginx 8080:80 --address=0.0.0.0

kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml 
#install/deploy metrics-server plugin

#```
# Edit the Metrics Server Deployment
kubectl -n kube-system edit deployment metrics-server

# Add the security bypass to deployment under container.args
- --kubelet-insecure-tls
- --kubelet-preferred-address-types=InternalIP,Hostname,ExternalIP

#Restart the deployment
kubectl -n kube-system rollout restart deployment metrics-server

#Verify if the metrics server is running
kubectl get pods -n kube-system
kubectl top nodes
#-----

kubectl explain deployments --recursive > deployment.txt # get all fields in deployment

kubectl create deployment nginx-deployment --image=nginx --dry-run=client -o yaml # create a deployment in yaml format

kubectl expose deployment nginx-deployment --port=80 --target-port=80 --type=NodePort --dry-run=client -o yaml # create a service in yaml format

kind load docker-image trainwithshubham/ai-bankapp:k8s --name sg-cluster # load docker image into kind cluster