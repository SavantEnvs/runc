FROM gcr.io/oss-fuzz-base/base-builder-go

RUN apt-get update --fix-missing && apt-get install -y --fix-missing \
    pkg-config libseccomp-dev

COPY . runc
RUN rm -rf runc/mayhem

WORKDIR $SRC/runc

ENV FUZZING_LANGUAGE=go
RUN compile_go_fuzzer github.com/opencontainers/runc/libcontainer/configs FuzzUnmarshalJSON configs_fuzzer
