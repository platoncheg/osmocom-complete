FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    wget \
    gnupg2 \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Add Osmocom repository with correct URL and GPG key
RUN wget -O /etc/apt/trusted.gpg.d/osmocom.asc https://obs.osmocom.org/projects/osmocom/public_key

RUN echo "deb [signed-by=/etc/apt/trusted.gpg.d/osmocom.asc] https://downloads.osmocom.org/packages/osmocom:/latest/xUbuntu_22.04/ ./" > /etc/apt/sources.list.d/osmocom.list

RUN apt-get update && apt-get install -y \
    osmo-stp \
    && rm -rf /var/lib/apt/lists/*

COPY osmo-stp.cfg /etc/osmocom/osmo-stp.cfg

EXPOSE 4239 2905 14001

CMD ["osmo-stp", "-c", "/etc/osmocom/osmo-stp.cfg"]