#include .env
SHELL := /bin/bash
UNAME := $(shell uname)

.PHONY: setup proto githooks gofmt check-gofmt
# local development setup for protobuf, virtualbox (for minikube), and go libraries for protobufsetup:
	@echo "Setting up project"
	brew list protobuf &>/dev/null || brew install protobuf
	brew cask install virtualbox
	go get -u github.com/golang/protobuf/proto
	go get -u github.com/gogo/protobuf/protoc-gen-gogofaster
	go mod download
	minikube config set memory 4096

# generate protobuf files from a proto/directory
proto:
	@echo "Building proto files..."
	for f in `find ./proto -type f -name "*.proto"`; do \
		protoc -Ithird_party/googleapis -Iproto --gogofaster_out=plugins=grpc:proto/. $$f; \
		echo compiled: $$f;\
	done

# automate local githooks by putting githook scripts in a .githooks folder
githooks:
	@echo "Setting githooks path..."
	git config core.hooksPath .githooks

gofmt:
	@echo "Formatting files..."
	gofmt -s -l -w .

check-gofmt:
	@echo "Validating file formatting..."
	$(eval unformatted:=$(shell (gofmt -s -l .)))
	@if [ "$(unformatted)" != "" ]; then echo "go files need to be formatted:\n $(unformatted)" && exit 1; fi

.PHONY: login mini-vbox-setup deploy_k8-dashboard delete-all-pods delete-all-deployments delete-all-services
login:
	docker login -u $(ARTIFACTORY_USER) -p $(ARTIFACTORY_API_TOKEN) $(ARTIFACTORY_URL)

mini-vbox-setup:
	minikube stop; \
	minikube delete; \
	minikube config set memory 8192; \
	minikube config set cpus 2; \
	minikube start --driver=virtualbox --disk-size=40GB;

deploy_k8-dashboard:
	kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.0.0/aio/deploy/recommended.yaml;
	kubectl apply -f deployment/k8-dashboard.yml;
	@echo ""
	@echo ""
	export SECRET=$(shell kubectl -n kubernetes-dashboard get secret | grep "admin-user" | awk '{print $1}'); \
	kubectl -n kubernetes-dashboard describe secret $$SECRET;
	@echo ""
	@echo "======================================================================================================================="
	@echo ""
	@echo -e "Use the above admin-user token ^^^ to log into the dashboard here:\nhttp://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/"
	@echo ""
	@echo "======================================================================================================================="
	@echo ""
	kubectl proxy

delete-all-pods: set_namespace
	kubectl delete --all pods

delete-all-deployments: set_namespace
	kubectl delete --all deployments

delete-all-services: set_namespace
	kubectl delete --all services


.PHONY: set_namespace deploy_nfs-all deploy_local-pv deploy_nfs-server deploy_nfs-pv delete_local-pv delete_nfs delete_nfs-pv delete_nfs_all test_nfs tail_nfs-server
deploy_nfs-all: set_namespace deploy_local-pv deploy_nfs-server deploy_nfs-pv

delete_nfs-all: delete_nfs-server delete_nfs-pv delete_local-pv

# adjust the namespace if needed
set_namespace:
	kubectl config set-context --current --namespace=default

deploy_local-pv: set_namespace
	nfs/set_local_pv
	kubectl apply -f deployment/_tmp_local-pv.yml

deploy_nfs-server:
	@echo "Building docker image..."
	eval $$(minikube docker-env); \
	docker build . -t nfs-server:latest -f nfs/Dockerfile
	kubectl apply -f deployment/nfs-server.yml

deploy_nfs-pv:
	# returns the clusterIP of the nfs-server (must be running) - not ideal but it is dynamic
	CIP=$(shell kubectl get svc -l app=nfs -o go-template --template='{{range .items}}{{printf "%s\n" .spec.clusterIP}}{{end}}'); \
	sed "s/{{nfs-server.default.svc.cluserIP}}/$$CIP/" deployment/nfs-pv.yml > deployment/_tmp_nfs-pv.yml
	kubectl apply -f deployment/_tmp_nfs-pv.yml

delete_local-pv:
	kubectl --request-timeout 60s delete -f deployment/_tmp_local-pv.yml
	rm deployment/_tmp_local-pv.yml || true

delete_nfs-server:
	kubectl delete -f deployment/nfs-server.yml || true

delete_nfs-pv:
	kubectl delete -f deployment/_tmp_nfs-pv.yml || true
	rm deployment/_tmp_nfs-pv.yml || true

test_nfs:
	nfs/nfs_test

tail_nfs-server:
	kubectl logs -f $(shell sh -c "kubectl get pods | grep nfs-server | grep Running" | awk '{print $$1}')
