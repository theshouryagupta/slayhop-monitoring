#!/bin/bash
set -e

# Copy pipeline configs from read-only mount to writable location
echo "Copying pipeline configurations..."
mkdir -p /usr/share/logstash/pipeline/
cp -r /config-ro/* /usr/share/logstash/pipeline/
chown -R logstash:logstash /usr/share/logstash/pipeline/

# Set proper permissions
chmod -R 755 /usr/share/logstash/pipeline/
find /usr/share/logstash/pipeline -type f -exec chmod 644 {} \;

# Start Logstash with the correct user using standard su
echo "Starting Logstash..."
exec su -c "/usr/local/bin/docker-entrypoint $*" logstash