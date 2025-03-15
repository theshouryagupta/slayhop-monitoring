#!/bin/bash

# Wait for Elasticsearch to start
until curl -s http://elasticsearch:9200 >/dev/null; do
    echo "Waiting for Elasticsearch to start..."
    sleep 5
done

echo "Elasticsearch started, setting up users..."

# Reset the kibana_system user password
curl -X POST -u elastic:$ELASTIC_PASSWORD "http://elasticsearch:9200/_security/user/kibana_system/_password" -H "Content-Type: application/json" -d "{\"password\":\"$KIBANA_SYSTEM_PASSWORD\"}"

echo "Kibana system user password updated."

# Create roles and users for your specific use cases
# Example: Create a user for Logstash
curl -X POST -u elastic:$ELASTIC_PASSWORD "http://elasticsearch:9200/_security/role/logstash_writer" -H "Content-Type: application/json" -d '
{
  "cluster": ["monitor", "manage_index_templates", "manage_ilm"],
  "indices": [
    {
      "names": ["logstash-*", "celery-*"],
      "privileges": ["write", "create", "create_index", "manage", "manage_ilm"]
    }
  ]
}'

echo "Setup completed successfully."