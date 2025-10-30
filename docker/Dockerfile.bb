FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies
RUN apt-get update && apt-get install -y \
    wget \
    gnupg2 \
    net-tools \
    git \
    build-essential \
    libtool \
    autoconf \
    automake \
    pkg-config \
    make \
    gcc \
    g++ \
    libfftw3-dev \
    libgsl-dev \
    libusb-1.0-0-dev \
    libtalloc-dev \
    libpcsclite-dev \
    netcat-openbsd \
    telnet \
    && rm -rf /var/lib/apt/lists/*

# Add Osmocom repository
RUN wget -O /etc/apt/trusted.gpg.d/osmocom.asc https://obs.osmocom.org/projects/osmocom/public_key
RUN echo "deb [signed-by=/etc/apt/trusted.gpg.d/osmocom.asc] https://downloads.osmocom.org/packages/osmocom:/latest/xUbuntu_22.04/ ./" > /etc/apt/sources.list.d/osmocom.list


RUN apt-get update && apt-get install -y libosmocore-dev && rm -rf /var/lib/apt/lists/*

# Build libosmo-gprs
WORKDIR /tmp
RUN git clone https://gitea.osmocom.org/osmocom/libosmo-gprs libosmo-gprs
WORKDIR /tmp/libosmo-gprs
RUN autoreconf -fi && ./configure && make && make install && ldconfig

# Clone and build OsmocomBB
WORKDIR /opt
RUN git clone https://gitea.osmocom.org/phone-side/osmocom-bb osmocom-bb
WORKDIR /opt/osmocom-bb
RUN git submodule update --init --recursive

# Build osmocon (Layer1 controller)
RUN cd src/host/osmocon && autoreconf -fi && ./configure && make

# Build mobile app
RUN cd src/host/layer23 && autoreconf -fi && ./configure && make

# Build virtphy (virtual Layer1)
RUN cd src/host/virt_phy && autoreconf -fi && ./configure && make

RUN mkdir -p /data /tmp

COPY config/mobile.cfg /data/mobile.cfg

EXPOSE 4247

WORKDIR /opt/osmocom-bb

# Start 3 virtphy instances (one per mobile station), then start mobile app
CMD ["bash", "-c", "src/host/virt_phy/src/virtphy --l1ctl-sock /tmp/osmocom_l2_1 & src/host/virt_phy/src/virtphy --l1ctl-sock /tmp/osmocom_l2_2 & src/host/virt_phy/src/virtphy --l1ctl-sock /tmp/osmocom_l2_3 & sleep 3 && exec src/host/layer23/src/mobile/mobile -c /data/mobile.cfg"]