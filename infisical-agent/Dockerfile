FROM alpine:3.20
ARG INFISICAL_CLI_VERSION=0.43.128
ARG TARGETARCH=amd64
RUN apk add --no-cache ca-certificates wget bash tar \
 && cd /tmp \
 && wget -qO cli.tgz "https://github.com/Infisical/cli/releases/download/v${INFISICAL_CLI_VERSION}/cli_${INFISICAL_CLI_VERSION}_linux_${TARGETARCH}.tar.gz" \
 && tar -xzf cli.tgz \
 && mv infisical /usr/local/bin/infisical \
 && chmod +x /usr/local/bin/infisical \
 && rm cli.tgz
WORKDIR /home/agent
ENTRYPOINT ["/usr/local/bin/infisical"]
CMD ["agent", "--config", "/config/agent-config.yaml"]
