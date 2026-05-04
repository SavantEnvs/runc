FROM golang:1.23 AS builder

RUN apt-get update && apt-get install -y pkg-config libseccomp-dev clang

COPY . /go/src/github.com/opencontainers/runc
WORKDIR /go/src/github.com/opencontainers/runc
RUN rm -rf mayhem

# Build standalone fuzzer using the existing UnmarshalJSON logic
COPY mayhem/configs_fuzzer_native.go /tmp/configs_fuzzer_main.go
RUN mkdir -p /tmp/fuzz && \
    cp /tmp/configs_fuzzer_main.go /tmp/fuzz/main.go && \
    cd /tmp/fuzz && \
    go mod init configs_fuzzer && \
    go mod edit -replace github.com/opencontainers/runc=/go/src/github.com/opencontainers/runc && \
    go mod tidy && \
    go build -o /out/configs_fuzzer .

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends libseccomp2
COPY --from=builder /out/configs_fuzzer /out/configs_fuzzer
