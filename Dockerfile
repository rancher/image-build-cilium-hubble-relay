ARG GO_IMAGE=rancher/hardened-build-base:v1.26.4b1
ARG BCI_IMAGE=registry.suse.com/bci/bci-nano:16.0

# Image that provides cross compilation tooling.
FROM --platform=$BUILDPLATFORM rancher/mirrored-tonistiigi-xx:1.6.1 AS xx

FROM --platform=$BUILDPLATFORM ${GO_IMAGE} AS builder
COPY --from=xx / /
RUN apk add --no-cache file make git clang lld
ARG TARGETPLATFORM
RUN set -x && xx-apk --no-cache add musl-dev gcc lld

ARG PKG
ARG TAG
RUN git clone --depth=1 https://${PKG}.git $GOPATH/src/${PKG}
WORKDIR $GOPATH/src/${PKG}
RUN git fetch --all --tags --prune
RUN git checkout tags/${TAG} -b ${TAG}

ARG TARGETARCH
RUN xx-go --wrap && \
    GO_LDFLAGS="-X github.com/cilium/cilium/pkg/version.ciliumVersion=$(cat VERSION)" \
    go-build-static.sh -mod=vendor -tags osusergo,netgo -gcflags=-trimpath=${GOPATH}/src \
        -o "/usr/local/bin/hubble-relay" ./hubble-relay
RUN xx-verify --static /usr/local/bin/hubble-relay
RUN if [ "$(xx-info arch)" = "amd64" ]; then \
        go-assert-boring.sh /usr/local/bin/hubble-relay; \
    fi

FROM ${BCI_IMAGE} AS hardened-cilium-hubble-relay
LABEL org.opencontainers.image.description="Cilium Hubble Relay"
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=builder /usr/local/bin/hubble-relay /usr/bin/hubble-relay
ENTRYPOINT ["/usr/bin/hubble-relay", "serve"]
