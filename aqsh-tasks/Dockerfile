FROM ghcr.io/null-ptr-exception/aqsh:0.4.0

ARG KUBECTL_VERSION=v1.30.0

RUN apt-get update && apt-get install -y --no-install-recommends jq python3 curl ca-certificates && rm -rf /var/lib/apt/lists/* \
    && curl -fsSLo /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/$(dpkg --print-architecture)/kubectl" \
    && curl -fsSLo /tmp/kubectl.sha256 "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/$(dpkg --print-architecture)/kubectl.sha256" \
    && echo "$(cat /tmp/kubectl.sha256)  /usr/local/bin/kubectl" | sha256sum -c - \
    && chmod +x /usr/local/bin/kubectl \
    && rm -f /tmp/kubectl.sha256

COPY tasks.yaml /etc/aqsh/tasks.yaml
COPY --chmod=0755 scripts/ /tasks/
