FROM gcr.io/oss-fuzz-base/base-builder-go

RUN for i in 1 2 3 4 5; do \
      apt-get update --fix-missing && \
      apt-get install -y --fix-missing pkg-config libseccomp-dev && break || \
      { echo "Attempt $i failed, retrying..."; sleep 10; }; \
    done

# Put runc in the GOPATH location compile_go_fuzzer expects
COPY . $GOPATH/src/github.com/opencontainers/runc
RUN rm -rf $GOPATH/src/github.com/opencontainers/runc/mayhem

WORKDIR $GOPATH/src/github.com/opencontainers/runc

ENV FUZZING_LANGUAGE=go SANITIZER=address FUZZING_ENGINE=libfuzzer

# Compile libFuzzer engine first (creates /usr/lib/libFuzzingEngine.a)
RUN compile_libfuzzer

# Install go-fuzz tooling required by compile_go_fuzzer
RUN go install github.com/dvyukov/go-fuzz/go-fuzz@latest github.com/dvyukov/go-fuzz/go-fuzz-build@latest

RUN compile_go_fuzzer github.com/opencontainers/runc/libcontainer/configs FuzzUnmarshalJSON configs_fuzzer
