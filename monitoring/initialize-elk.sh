#!/bin/bash

# Check if this is a full reset command
if [ "$1" == "reset" ]; then
  echo "Performing full reset..."
  docker compose down -v
  docker volume rm monitoring_elasticsearch-data || true
  sleep 5
fi

# Check if Elasticsearch is running
ES_RUNNING=$(docker ps --filter "name=elasticsearch" --format "{{.Names}}" | wc -l)

if [ "$ES_RUNNING" -eq "0" ]; then
  echo "Starting Elasticsearch only first..."
  docker compose up -d elasticsearch
  echo "Waiting for Elasticsearch to start (30 seconds)..."
  sleep 30
else
  echo "Elasticsearch is already running."
fi

# Start or restart the remaining services
echo "Starting/restarting Kibana and Logstash..."
docker compose up -d

echo "ELK Stack is starting up. Give it a minute to initialize."
echo "Elasticsearch: http://your-server-ip:9200"
echo "Kibana: http://your-server-ip:5601"
echo "Default credentials: elastic / ${ELASTIC_PASSWORD}"