# build stage
FROM golang:1.18.1-stretch AS build-env
ADD . /src
ENV CGO_ENABLED=0
WORKDIR /src
RUN make

# final stage
FROM registry.access.redhat.com/ubi8:8.8
WORKDIR /app
COPY --from=build-env /src/bin/linux-amd64/ovs-exporter /app/
USER 65534
EXPOSE 9475
ENTRYPOINT ["/app/ovs-exporter"]
