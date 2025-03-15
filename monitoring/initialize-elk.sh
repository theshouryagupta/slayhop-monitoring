#!/bin/bash

# Stop and remove all existing containers
echo "Stopping and removing existing containers..."
docker compose down -v

# Remove existing data volume
echo "Removing existing Elasticsearch data..."
docker volume rm monitoring_elasticsearch-data || true

# Create required directories if they don't exist
mkdir -p logstash/config logstash/pipeline

# Update logstash.yml if it exists
if [ -f "logstash/config/logstash.yml" ]; then
  echo "Updating logstash.yml..."
  cat > logstash/config/logstash.yml << EOL
http.host: "0.0.0.0"
xpack.monitoring.elasticsearch.hosts: [ "http://elasticsearch:9200" ]
xpack.monitoring.elasticsearch.username: elastic
xpack.monitoring.elasticsearch.password: "${ELASTIC_PASSWORD}"
EOL
fi

# Start the services
echo "Starting services..."
docker compose up -d

# Wait for Elasticsearch to be healthy
echo "Waiting for Elasticsearch to be healthy..."
until docker exec -it elasticsearch curl --silent --fail -u elastic:${ELASTIC_PASSWORD} http://localhost:9200/_cluster/health?pretty; do
  echo "Elasticsearch is not ready yet - waiting 10 seconds..."
  sleep 10
done

echo "Elasticsearch is up and running!"

# Wait for Kibana to be available
echo "Waiting for Kibana to start..."
until curl --silent --fail http://localhost:5601/api/status; do
  echo "Kibana is not ready yet - waiting 10 seconds..."
  sleep 10
done

echo "Kibana is up and running!"

echo "ELK stack has been successfully initialized!"
echo "You can access Kibana at: http://localhost:5601"
echo "Default credentials: elastic / ${ELASTIC_PASSWORD}"