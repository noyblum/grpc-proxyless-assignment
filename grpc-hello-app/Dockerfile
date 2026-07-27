# Multi-stage build: generates the protobuf stubs, compiles both binaries
# statically, and ships them in a distroless image. The same image serves as
# server (default entrypoint) and client (override command with /client).
#
# The build stage runs on the host's native platform (BUILDPLATFORM) and
# cross-compiles to the target: running protoc/go under QEMU emulation on
# Apple Silicon is slow and crashes the Go toolchain.
FROM --platform=$BUILDPLATFORM golang:1.23-alpine AS build
ARG TARGETOS
ARG TARGETARCH

RUN apk add --no-cache protobuf protobuf-dev

WORKDIR /src
COPY go.mod ./
COPY . .

# Pin the protoc plugins and generate gen/helloworld from the proto.
RUN go install google.golang.org/protobuf/cmd/protoc-gen-go@v1.36.1 && \
    go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@v1.5.1
ENV PATH="${PATH}:/root/go/bin"
RUN protoc \
      --go_out=. --go_opt=module=github.com/noyblumenfeld/grpc-hello-app \
      --go-grpc_out=. --go-grpc_opt=module=github.com/noyblumenfeld/grpc-hello-app \
      proto/helloworld.proto

RUN go mod tidy && \
    CGO_ENABLED=0 GOOS=${TARGETOS:-linux} GOARCH=${TARGETARCH} go build -trimpath -o /out/server ./cmd/server && \
    CGO_ENABLED=0 GOOS=${TARGETOS:-linux} GOARCH=${TARGETARCH} go build -trimpath -o /out/client ./cmd/client

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/server /server
COPY --from=build /out/client /client
ENTRYPOINT ["/server"]
