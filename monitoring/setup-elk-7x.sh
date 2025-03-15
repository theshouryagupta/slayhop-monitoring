#!/bin/bash

# Check if .env file exists and load it
if [ -f .env ]; then
  echo "Loading environment variables from .env file..."
  export $(grep -v '^#' .env | xargs)
else
  echo "No .env file found. Make sure ELASTIC_PASSWORD is set in your environment."
  if [ -z "$ELASTIC_PASSWORD" ]; then
    echo "ERROR: ELASTIC_PASSWORD environment variable is not set."
    echo "Please create a .env file based on .env.template or set the variable manually."
    exit 1
  fi
fi

# Stop and remove all containers
echo "Stopping and removing all containers..."
docker compose down

# Create required directory structure
echo "Creating directory structure..."
mkdir -p logstash/pipeline

# Ensure the directory is writable by everyone (for Docker)
chmod 777 logstash/pipeline

# Create a minimal working pipeline with hardcoded password
echo "Creating minimal logstash pipeline configuration..."
cat > logstash/pipeline/logstash.conf << EOL
input {
  beats {
    port => 5044
  }
}

output {
  elasticsearch {
    hosts => ["elasticsearch:9200"]
    user => "elastic"
    password => "${ELASTIC_PASSWORD}"
    index => "logstash-%{+YYYY.MM.dd}"
  }
}
EOL

# Make sure the pipeline configuration file is readable
chmod 644 logstash/pipeline/logstash.conf

# Start Elasticsearch
echo "Starting Elasticsearch..."
docker compose up -d elasticsearch

# Wait for Elasticsearch to be ready
echo "Waiting for Elasticsearch to start (this may take a minute)..."
until curl -s -u elastic:${ELASTIC_PASSWORD} http://localhost:9200/_cluster/health | grep -q '"status":\("yellow"\|"green"\)'; do
  echo "Waiting for Elasticsearch..."
  sleep 10
done

# Start Kibana and Logstash
echo "Elasticsearch is ready. Starting Kibana and Logstash..."
docker compose up -d kibana logstash

echo "ELK stack is starting up."
echo "Elasticsearch should be available at: http://your-server-ip:9200"
echo "Kibana should be available at: http://your-server-ip:5601"
echo "Default credentials: elastic / [password from .env file]"
echo ""
echo "NOTE: Kibana should be ready within 1-2 minutes."
echo "You can check logs with:"
echo "docker logs -f elasticsearch"
echo "docker logs -f kibana"
echo "docker logs -f logstash"