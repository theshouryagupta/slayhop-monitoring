#!/bin/bash

set -e

# Stop and remove all existing containers
echo "Stopping and removing existing containers..."
docker compose down -v || true

# Remove existing data volume
echo "Removing existing Elasticsearch data..."
docker volume rm monitoring_elasticsearch-data || true

# Create required directories if they don't exist
mkdir -p logstash/config logstash/pipeline

# Update logstash.yml
echo "Updating logstash.yml..."
cat > logstash/config/logstash.yml << EOL
http.host: "0.0.0.0"
xpack.monitoring.enabled: true
xpack.monitoring.elasticsearch.hosts: [ "http://elasticsearch:9200" ]
xpack.monitoring.elasticsearch.username: elastic
xpack.monitoring.elasticsearch.password: "${ELASTIC_PASSWORD}"

# Add specific Logstash retry policy to fix the error
action.auto_create_index: true
pipeline.ordered: auto
pipeline.batch.size: 125
pipeline.batch.delay: 50
queue.type: memory
queue.max_events: 1000

# Increase retry settings
output.elasticsearch.retry.initial_backoff: "1s"
output.elasticsearch.retry.max_backoff: "60s"
output.elasticsearch.retry.backoff_type: "exponential"
output.elasticsearch.retry.max_retries: 5
EOL

# Check if elasticsearch is already running (possibly from a previous attempt)
if docker ps | grep -q elasticsearch; then
  echo "Stopping existing Elasticsearch container..."
  docker stop elasticsearch || true
  sleep 5
fi

# Start only Elasticsearch first
echo "Starting Elasticsearch..."
docker compose up -d elasticsearch

# Wait for Elasticsearch to be healthy
echo "Waiting for Elasticsearch to be healthy..."
MAX_RETRIES=30
COUNT=0
while ! docker exec -it elasticsearch curl --silent --fail -u elastic:${ELASTIC_PASSWORD} http://localhost:9200/_cluster/health?pretty; do
  echo "Elasticsearch is not ready yet - waiting 10 seconds..."
  sleep 10
  COUNT=$((COUNT+1))
  if [ $COUNT -ge $MAX_RETRIES ]; then
    echo "Elasticsearch did not become ready in time. Checking logs:"
    docker logs elasticsearch
    echo "Restarting from scratch..."
    docker compose down -v
    docker compose up -d elasticsearch
    COUNT=0
  fi
done

echo "Elasticsearch is up and running!"

# Start the remaining services
echo "Starting Kibana and Logstash..."
docker compose up -d kibana logstash

# Wait for Kibana to be available
echo "Waiting for Kibana to start..."
MAX_RETRIES=30
COUNT=0
while ! curl --silent --fail http://localhost:5601/api/status; do
  echo "Kibana is not ready yet - waiting 10 seconds..."
  sleep 10
  COUNT=$((COUNT+1))
  if [ $COUNT -ge $MAX_RETRIES ]; then
    echo "Kibana did not become ready in time. Checking logs:"
    docker logs kibana
    break
  fi
done

echo "ELK stack has been initialized! If Kibana is not yet running, check the logs with 'docker logs kibana'."
echo "You can access Kibana at: http://localhost:5601"
echo "Default credentials: elastic / ${ELASTIC_PASSWORD}"

# Print service status
echo "Current status of services:"
docker compose ps