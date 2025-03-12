#!/bin/bash
# Monitoring Server Setup Script with Caddy

# Exit on error
set -e

# Display banner
echo "=================================================="
echo "Monitoring Server Setup with Caddy"
echo "=================================================="

# Create necessary directories
echo "Creating directory structure..."
mkdir -p logstash/config logstash/pipeline caddy logs

# Copy example .env file if .env doesn't exist
if [ ! -f .env ]; then
  echo "Creating .env file from example..."
  cp .env.example .env
  echo "Please edit the .env file with your actual configuration values."
  echo "Then run this script again."
  exit 0
fi

# Load environment variables
export $(grep -v '^#' .env | xargs)

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
  echo "Docker is not installed. Installing Docker..."
  curl -fsSL https://get.docker.com -o get-docker.sh
  sh get-docker.sh
  rm get-docker.sh
fi

# Check if Docker Compose is installed
if ! command -v docker-compose &> /dev/null; then
  echo "Docker Compose is not installed. Installing Docker Compose..."
  sudo curl -L "https://github.com/docker/compose/releases/download/v2.17.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
  sudo chmod +x /usr/local/bin/docker-compose
fi

# Generate Elasticsearch password hash if it doesn't exist in the .env file
if grep -q "ELASTIC_PASSWORD_HASH=changeme" .env; then
  echo "Generating Elasticsearch password hash..."
  # Use caddy to generate the hash
  HASH=$(docker run --rm caddy:2.6.4 caddy hash-password -plaintext "${ELASTIC_PASSWORD}")
  # Update the .env file
  sed -i "s|ELASTIC_PASSWORD_HASH=changeme|ELASTIC_PASSWORD_HASH=${HASH}|g" .env
  echo "Password hash generated and updated in .env file."
fi

# Set system limits for Elasticsearch
echo "Setting system limits for Elasticsearch..."
# Increase max file descriptors
if [ -f /etc/security/limits.conf ]; then
  grep -q "elasticsearch - nofile 65535" /etc/security/limits.conf || sudo bash -c "echo 'elasticsearch - nofile 65535' >> /etc/security/limits.conf"
fi

# Set vm.max_map_count
if [ -f /etc/sysctl.conf ]; then
  grep -q "vm.max_map_count=262144" /etc/sysctl.conf || sudo bash -c "echo 'vm.max_map_count=262144' >> /etc/sysctl.conf"
  sudo sysctl -w vm.max_map_count=262144
fi

# Start the monitoring stack
echo "Starting the monitoring stack..."
docker-compose pull
docker-compose up -d

echo "------------------------------------------------------"
echo "Monitoring stack is now running!"
echo "------------------------------------------------------"
echo "Kibana:        https://monitoring.slayhop.com/"
echo "Flower:        https://flower.slayhop.com/"
echo "Elasticsearch: https://elasticsearch.slayhop.com"
echo "------------------------------------------------------"
echo "It might take a minute for all services to fully start."
echo "Check status with: docker-compose ps"
echo "------------------------------------------------------"