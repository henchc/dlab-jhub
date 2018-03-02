#! /bin/sh

# give docker image as 1st argument if provided
DOCKER=$1
DOCKER=${DOCKER:=henchc/rockyter2}

GITREPO=$2
GITREPO=${GITREPO:=https://github.com/dlab-berkeley/python-fundamentals.git}

NODES=$3
NODES=${NODES:=1}

# get random secret strings
CONFIG1=$(cat config_template.yaml)
S1=$(openssl rand -hex 32)
S2=$(openssl rand -hex 32)

# edit and write config.yaml
CONFIG2="${CONFIG1/SECRET1/$S1}"
CONFIG3="${CONFIG2/SECRET2/$S2}"
CONFIG4="${CONFIG3/DOCKER_IMAGE/$DOCKER}"
CONFIG5="${CONFIG4/REPO/$GITREPO}"
echo "$CONFIG5" > config.yaml

# install kubectl
gcloud components install kubectl

# create cluster with autorepair
gcloud beta container clusters create dlabhub \
        --num-nodes=$NODES \
        --machine-type=n1-highmem-2 \
        --zone=us-central1-b \
        --enable-autorepair \
        --enable-autoupgrade

# get and init helm
curl https://raw.githubusercontent.com/kubernetes/helm/master/scripts/get | bash
helm init

# add jhub helm charts
helm repo add jupyterhub https://jupyterhub.github.io/helm-chart/
helm repo update

# retry until tiller active
while [ $? -ne 0 ]; do
    echo "Retrying..."
    sleep 5
    helm repo update
done

kubectl create serviceaccount --namespace kube-system tiller
kubectl create clusterrolebinding tiller-cluster-rule --clusterrole=cluster-admin --serviceaccount=kube-system:tiller
kubectl patch deploy --namespace kube-system tiller-deploy -p '{"spec":{"template":{"spec":{"serviceAccount":"tiller"}}}}'      
helm init --service-account tiller --upgrade

# install hub
# https://github.com/jupyterhub/helm-chart/tree/gh-pages
helm install jupyterhub/jupyterhub \
    --version=v0.6 \
    --name=jhub \
    --namespace=dlabhub \
    -f config.yaml

# retry until docker image is fully pulled
while [ $? -ne 0 ]; do
    sleep 5
    echo "Retrying..."
    helm install jupyterhub/jupyterhub \
        --version=0.5.0-b2ac9a5 \
        --name=jhub \
        --namespace=dlabhub \
        -f config.yaml
done

# print pods
kubectl --namespace=dlabhub get pod

# wait until external ip address is established
kubectl --namespace=dlabhub get svc | grep pending
while [ $? -ne 1 ]; do
    echo "IP Pending..."
    sleep 5
    kubectl --namespace=dlabhub get svc | grep pending
done

# print IP
echo ""
echo "Your JupyterHub can be accessed at:"
kubectl --namespace=dlabhub get svc
