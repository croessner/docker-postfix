IMAGE_NAME ?= postfix
TAG ?= latest
EXAMPLE_CERT_DIR := examples/certs
EXAMPLE_TLS_CERT := $(EXAMPLE_CERT_DIR)/tls.crt
EXAMPLE_TLS_KEY := $(EXAMPLE_CERT_DIR)/tls.key
EXAMPLE_TLS_CA := $(EXAMPLE_CERT_DIR)/ca.crt

.PHONY: build push sbom-local sbom-registry run test-smoke compose-up compose-down compose-cert

build:
	docker build -t $(IMAGE_NAME):$(TAG) .

push:
	docker buildx build \
	  --platform linux/amd64,linux/arm64 \
	  --pull \
	  --attest type=provenance,mode=max \
	  --attest type=sbom \
	  -t $(IMAGE_NAME):$(TAG) \
	  --push .

sbom-local:
	rm -rf dist/sbom-local
	docker buildx build \
	  --sbom=true \
	  --output type=local,dest=dist/sbom-local .

sbom-registry:
	mkdir -p dist/sbom
	docker buildx imagetools inspect $(IMAGE_NAME):$(TAG) \
	  --format '{{ json .SBOM }}' > dist/sbom/$(TAG).sbom.json

run:
	docker run --rm -it \
	  --name postfix \
	  -p 25:25 -p 465:465 -p 587:587 \
	  --env-file .env \
	  -v $$(pwd)/examples/custom-config:/etc/postfix/custom-config:ro \
	  -v $$(pwd)/examples/maps:/etc/postfix/maps:ro \
	  -v $$(pwd)/examples/init:/docker-entrypoint-init.d:ro \
	  -v $$(pwd)/examples/certs:/etc/postfix/certs:ro \
	  $(IMAGE_NAME):$(TAG)

test-smoke:
	docker run --rm $(IMAGE_NAME):$(TAG) postfix check

compose-cert:
	mkdir -p $(EXAMPLE_CERT_DIR)
	openssl req -x509 -newkey rsa:2048 -sha256 -nodes \
	  -days 7 \
	  -subj '/CN=mail.example.org' \
	  -addext 'subjectAltName=DNS:localhost,DNS:postfix,DNS:mail.example.org,IP:127.0.0.1' \
	  -keyout $(EXAMPLE_TLS_KEY) \
	  -out $(EXAMPLE_TLS_CERT)
	cp $(EXAMPLE_TLS_CERT) $(EXAMPLE_TLS_CA)
	chmod 0644 $(EXAMPLE_TLS_CERT) $(EXAMPLE_TLS_KEY) $(EXAMPLE_TLS_CA)

compose-up: compose-cert
	IMAGE_NAME=$(IMAGE_NAME) TAG=$(TAG) docker compose -f examples/docker-compose.yml up --build

compose-down:
	IMAGE_NAME=$(IMAGE_NAME) TAG=$(TAG) docker compose -f examples/docker-compose.yml down -v
	rm -f $(EXAMPLE_TLS_CERT) $(EXAMPLE_TLS_KEY) $(EXAMPLE_TLS_CA)
