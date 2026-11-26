FROM alpine:3.24

# Install required tools
RUN apk add --no-cache \
    bash \
    curl \
    grep \
    coreutils

# Copy bootstrap script
COPY bootstrap.sh /bootstrap.sh
RUN chmod +x /bootstrap.sh

# Set working directory
WORKDIR /

# Run bootstrap script
ENTRYPOINT ["/bootstrap.sh"]