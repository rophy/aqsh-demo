FROM ghcr.io/null-ptr-exception/aqsh:0.4.0

RUN apt-get update && apt-get install -y --no-install-recommends jq python3 curl ca-certificates && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/$(dpkg --print-architecture)/kubectl" -o /usr/local/bin/kubectl \
    && chmod +x /usr/local/bin/kubectl

COPY tasks.yaml /etc/aqsh/tasks.yaml
COPY --chmod=0755 scripts/ /tasks/
