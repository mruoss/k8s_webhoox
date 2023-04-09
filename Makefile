KUBECONFIG_PATH?=./integration.yaml
CLUSTER_NAME=k8s-webhoox

integration.yaml: ## Create a kind cluster
	$(MAKE) cluster.delete cluster.create
	kind export kubeconfig --kubeconfig ${KUBECONFIG_PATH} --name "${CLUSTER_NAME}" 

.PHONY: cluster.delete
cluster.delete: ## Delete kind cluster
	- kind delete cluster --kubeconfig ${KUBECONFIG_PATH} --name "${CLUSTER_NAME}"
	rm -f ${KUBECONFIG_PATH}

.PHONY: cluster.create
cluster.create: ## Created kind cluster
	kind create cluster --wait 600s --name "${CLUSTER_NAME}" 

.PHONY: test
test: integration.yaml
test:
	kubectl config use-context kind-${CLUSTER_NAME}
	KUBECONFIG=${KUBECONFIG_PATH} mix test --include integration 

.PHONY: cover
cover: integration.yaml
cover:
	kubectl config use-context kind-${CLUSTER_NAME}
	KUBECONFIG=${KUBECONFIG_PATH} mix coveralls.html --include integration
