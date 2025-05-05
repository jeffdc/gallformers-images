GO ?= go
BIN_DIR := bin
PKGS := $(shell $(GO) list ./... | grep -v /vendor/)

.PHONY: test lint build clean

test:
	$(GO) test -v $(PKGS)

lint:
	$(GO) vet $(PKGS)
	staticcheck $(PKGS)

build: clean
	CGO_ENABLED=1 $(GO) build -o $(BIN_DIR)/imgsvc ./cmd/service
	CGO_ENABLED=1 $(GO) build -o $(BIN_DIR)/reprocess ./cmd/reprocess

clean:
	rm -rf $(BIN_DIR)
