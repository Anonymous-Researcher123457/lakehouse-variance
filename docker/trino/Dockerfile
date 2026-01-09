# Stage 1: Build node_exporter from Alpine
FROM alpine:3.17 AS nodeexporterbuilder
ENV NODE_EXPORTER_VERSION=1.6.0
RUN apk add --no-cache curl tar && \
    curl -LO https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz && \
    tar -xvf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz


# Stage 1: Install required utilities
FROM debian:bullseye AS sysstatbuilder
RUN apt-get update && apt-get install -y sysstat && rm -RF /var/lib/apt/lists/*



# Stage 2: Get a static BusyBox binary from the official BusyBox image
FROM busybox:latest AS busyboxstage
# BusyBox is available at /bin/busybox in this image

# Stage 3: Build Python from an older base to match glibc version and install requests
FROM python:3.10-slim-bullseye AS pythonbuilder
RUN pip install requests
RUN pip install argparse


# Stage 4: Final image based on Trino
FROM trinodb/trino:latest
ARG NODE_EXPORTER_VERSION=1.6.0
ARG JMX_EXPORTER_VERSION=0.19.0
USER root

COPY --from=nodeexporterbuilder /node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter /usr/local/bin/node_exporter
COPY --from=busyboxstage /bin/busybox /usr/local/bin/busybox
COPY --from=pythonbuilder /usr/local/bin/python3 /usr/local/bin/python3
COPY --from=pythonbuilder /usr/local/lib /usr/local/lib
COPY --from=sysstatbuilder /usr/bin/pidstat /usr/bin/pidstat
COPY --from=sysstatbuilder /usr/lib/ /usr/lib/

RUN chmod +x /usr/bin/pidstat

# Ensure the binaries are executable
RUN chmod +x /usr/local/bin/node_exporter /usr/local/bin/busybox /usr/local/bin/python3

# Create symlinks for common utilities in directories that are in the PATH.
RUN mkdir -p /bin /usr/bin /usr/local/bin && \
    ln -sf /usr/local/bin/busybox /usr/local/bin/ls && \
    ln -sf /usr/local/bin/busybox /usr/local/bin/ps && \
    ln -sf /usr/local/bin/busybox /usr/local/bin/top && \
    ln -sf /usr/local/bin/busybox /usr/bin/ls && \
    ln -sf /usr/local/bin/busybox /usr/bin/ps && \
    ln -sf /usr/local/bin/busybox /usr/bin/top && \
    ln -sf /usr/local/bin/busybox /bin/ls && \
    ln -sf /usr/local/bin/busybox /bin/ps && \
    ln -sf /usr/local/bin/busybox /bin/top

# Create a directory for JMX Exporter
RUN mkdir -p /opt/jmx_exporter
COPY jmx_prometheus_javaagent-1.1.0.jar /opt/jmx_exporter/jmx_prometheus_javaagent.jar
RUN chmod 644 /opt/jmx_exporter/jmx_prometheus_javaagent.jar
COPY --chmod=+x entrypoint.sh /entrypoint.sh

# ---------------------- Modify Trino Start Command ----------------------
ENV TRINO_JVM_OPTS="-javaagent:/opt/jmx_exporter/jmx_prometheus_javaagent.jar=9090:/etc/jmx-exporter-config.yml"
COPY --chmod=+x entrypoint.sh /entrypoint.sh
USER trino

ENTRYPOINT ["/entrypoint.sh"]
CMD ["trino", "launcher", "run", "${TRINO_JVM_OPTS}"]