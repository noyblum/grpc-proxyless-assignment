# Configuration ---------------------------------------------------------------
PROJECT_ID ?= my-gcp-project
REGION     ?= us-central1
REPO       ?= grpc-demo
IMAGE      ?= $(REGION)-docker.pkg.dev/$(PROJECT_ID)/$(REPO)/grpc-hello
TAG        ?= v0.1.0

# Local development ------------------------------------------------------------
.PHONY: proto
proto: ## Generate Go stubs from proto/helloworld.proto (requires protoc + plugins)
	protoc \
	  --go_out=. --go_opt=module=github.com/noyblumenfeld/grpc-hello-app \
	  --go-grpc_out=. --go-grpc_opt=module=github.com/noyblumenfeld/grpc-hello-app \
	  proto/helloworld.proto

.PHONY: build
build: proto ## Build server and client binaries locally
	go mod tidy
	CGO_ENABLED=0 go build -o bin/server ./cmd/server
	CGO_ENABLED=0 go build -o bin/client ./cmd/client

# Image ------------------------------------------------------------------------
.PHONY: docker-build
docker-build: ## Build the container image (proto generation happens in-image)
	docker build --platform linux/amd64 -t $(IMAGE):$(TAG) .

.PHONY: docker-push
docker-push: docker-build ## Push to Artifact Registry
	gcloud auth configure-docker $(REGION)-docker.pkg.dev --quiet
	docker push $(IMAGE):$(TAG)
