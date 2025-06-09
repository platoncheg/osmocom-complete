FROM ubuntu:22.04

# Avoid interactive prompts during build
ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    autoconf \
    automake \
    libtool \
    pkg-config \
    git \
    libtalloc-dev \
    libpcsclite-dev \
    libortp-dev \
    libsctp-dev \
    libmnl-dev \
    libdbi-dev \
    libdbd-sqlite3 \
    libsqlite3-dev \
    libc-ares-dev \
    libgnutls28-dev \
    libssl-dev \
    liburing-dev \
    libsystemd-dev \
    libusb-1.0-0-dev \
    libfftw3-dev \
    libgps-dev \
    telnet \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Create working directory
WORKDIR /opt/osmocom

# Clone and build libosmocore
RUN git clone https://gitea.osmocom.org/osmocom/libosmocore.git && \
    cd libosmocore && \
    autoreconf -fi && \
    ./configure --prefix=/usr/local \
        --disable-uring \
        --disable-pcsc \
        --disable-pseudotalloc \
        --disable-doxygen && \
    make -j$(nproc) && \
    make install && \
    ldconfig

# Clone and build libosmo-netif
RUN git clone https://gitea.osmocom.org/osmocom/libosmo-netif.git && \
    cd libosmo-netif && \
    autoreconf -fi && \
    ./configure --prefix=/usr/local && \
    make -j$(nproc) && \
    make install && \
    ldconfig

# Clone and build libosmo-sccp (SS7 stack)
RUN git clone https://gitea.osmocom.org/osmocom/libosmo-sccp.git && \
    cd libosmo-sccp && \
    autoreconf -fi && \
    ./configure --prefix=/usr/local && \
    make -j$(nproc) && \
    make install && \
    ldconfig

# Clone and build osmo-stp
RUN git clone https://gitea.osmocom.org/osmocom/libosmo-sigtran.git && \
    cd libosmo-sigtran && \
    autoreconf -fi && \
    ./configure --prefix=/usr/local && \
    make -j$(nproc) && \
    make install && \
    ldconfig

# Create config directory
RUN mkdir -p /etc/osmocom

# Copy configuration files
COPY osmo-stp.cfg /etc/osmocom/

# Expose ports
# 4239 - VTY interface
# 2905 - M3UA
# 14001 - SCCP
EXPOSE 4239 2905 14001

# Default command
CMD ["/usr/local/bin/osmo-stp", "-c", "/etc/osmocom/osmo-stp.cfg"]