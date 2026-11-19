# Endpoint Ubuntu con agente Wazuh (para M4 y M7). Lo construye quien mantiene el laboratorio
# (CI) y se distribuye ya construido; los estudiantes no construyen.
# SIN PROBAR en el entorno de desarrollo (sin acceso a packages.wazuh.com).
FROM ubuntu:24.04
ARG WAZUH_VERSION=4.14.6-1
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends curl gnupg ca-certificates lsb-release procps \
 && curl -fsSL https://packages.wazuh.com/key/GPG-KEY-WAZUH | gpg --dearmor -o /usr/share/keyrings/wazuh.gpg \
 && echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" > /etc/apt/sources.list.d/wazuh.list \
 && apt-get update && apt-get install -y --no-install-recommends wazuh-agent=${WAZUH_VERSION} \
 && rm -rf /var/lib/apt/lists/*
COPY endpoint-entry.sh /entry.sh
RUN chmod +x /entry.sh
ENTRYPOINT ["/entry.sh"]
