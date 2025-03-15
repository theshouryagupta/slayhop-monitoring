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
docker compose down -v

# Remove ALL volumes related to ELK
echo "Removing all ELK-related volumes..."
docker volume rm $(docker volume ls -q | grep elastic) 2>/dev/null || true
docker volume rm monitoring_elasticsearch-data 2>/dev/null || true

# Clean up any leftover Docker networks
echo "Cleaning up Docker networks..."
docker network rm monitoring_elk-network 2>/dev/null || true

# Create required directory structure
echo "Creating directory structure..."
mkdir -p logstash/config
mkdir -p logstash/pipeline

# Create logstash configuration
echo "Creating logstash configuration..."
cat > logstash/config/logstash.yml << EOL
http.host: "0.0.0.0"
path.config: /usr/share/logstash/pipeline
xpack.monitoring.elasticsearch.hosts: ["http://elasticsearch:9200"]
xpack.monitoring.elasticsearch.username: elastic
xpack.monitoring.elasticsearch.password: \${ELASTIC_PASSWORD}
EOL

# Create logstash pipeline
echo "Creating logstash pipeline configuration..."
cat > logstash/pipeline/01-beats-input.conf << EOL
input {
  beats {
    port => 5044
  }
}

filter {
  if "celery-service-1" in [tags] {
    mutate {
      add_field => { "[@metadata][app]" => "celery-service-1" }
    }
    
    if [message] =~ "ERROR" {
      mutate {
        add_tag => ["error"]
      }
    }
  }
  
  if "celery-service-2" in [tags] {
    mutate {
      add_field => { "[@metadata][app]" => "celery-service-2" }
    }
    
    if [message] =~ "ERROR" {
      mutate {
        add_tag => ["error"]
      }
    }
    
    # Extract task name if available
    if [message] =~ /\[([^\]]+)\(([^\)]+)\)\]/ {
      grok {
        match => { "message" => "\[%{DATA:task_name}\(%{DATA:task_id}\)\]" }
      }
    }
  }
  
  if [message] =~ /\[(\w+)\]/ {
    grok {
      match => { "message" => "\[%{LOGLEVEL:log_level}\]" }
    }
  }
  
  date {
    match => [ "timestamp", "ISO8601" ]
    target => "@timestamp"
    remove_field => [ "timestamp" ]
  }
}

output {
  elasticsearch {
    hosts => ["elasticsearch:9200"]
    user => "elastic"
    password => "\${ELASTIC_PASSWORD}"
    index => "celery-logs-%{[@metadata][app]}-%{+YYYY.MM.dd}"
  }
}
EOL

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
docker compose up -d

echo "ELK stack is starting up."
echo "Elasticsearch should be available at: http://your-server-ip:9200"
echo "Kibana should be available at: http://your-server-ip:5601"
echo "Default credentials: elastic / [password from .env file]"
echo ""
echo "NOTE: Kibana should be ready within 1-2 minutes."
echo "You can check status with: docker logs -f kibana"