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
mkdir -p logstash/pipeline

# Create logstash pipeline files
echo "Creating logstash pipeline configuration..."
cat > logstash/pipeline/01-beats-input.conf << EOL
input {
  beats {
    port => 5044
  }
}
EOL

cat > logstash/pipeline/02-filter.conf << EOL
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
EOL

cat > logstash/pipeline/03-output.conf << EOL
output {
  elasticsearch {
    hosts => ["elasticsearch:9200"]
    user => "elastic"
    password => "\${ELASTIC_PASSWORD}"
    index => "celery-logs-%{[@metadata][app]}-%{+YYYY.MM.dd}"
  }
}
EOL

# Create logstash entrypoint script
echo "Creating logstash entrypoint script..."
cat > logstash-entrypoint.sh << 'EOL'
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

# Start Logstash with the correct user
echo "Starting Logstash..."
exec su-exec logstash "$@"
EOL

# Set proper permissions
chmod +x logstash-entrypoint.sh

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
echo "You can check logs with:"
echo "docker logs -f elasticsearch"
echo "docker logs -f kibana"
echo "docker logs -f logstash"