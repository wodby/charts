#!/usr/bin/env bash
# Installs or migrates Zammad before the background worker starts. The other
# components wait in their entrypoint until the database is current.
set -o errexit -o nounset -o pipefail

cd /opt/zammad

# Zammad's own init creates or migrates the database and installs staged
# packages. Its Elasticsearch step writes the credentials into Ruby source code,
# which breaks on some characters, so it is skipped here and setup.rb configures
# Elasticsearch from the environment instead.
ELASTICSEARCH_ENABLED=false ELASTICSEARCH_USER='' ELASTICSEARCH_PASS='' \
  /opt/zammad/bin/docker-entrypoint zammad-init

echo "Applying Wodby settings..."
bundle exec rails r /opt/wodby/setup.rb

if [ -n "${ELASTICSEARCH_HOST:-}" ] && [ "${ELASTICSEARCH_ENABLED:-true}" != "false" ] \
  && [ "${ELASTICSEARCH_REINDEX:-true}" = "true" ]; then
  if bundle exec rails r "exit(SearchIndexBackend.index_exists?('Ticket') ? 0 : 1)"; then
    echo "The Elasticsearch index exists. No reindexing needed."
  else
    echo "The Elasticsearch index does not exist. Building it..."
    bundle exec rake zammad:searchindex:rebuild
  fi
fi
