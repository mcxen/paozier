#!/bin/bash
set -e
cd "$(dirname "$0")/.."

SOLR_VERSION="9.7.0"
SOLR_DIR="solr"

if [ -d "$SOLR_DIR/bin" ]; then
  echo "Solr already exists at $SOLR_DIR"
  exit 0
fi

echo "Downloading Solr $SOLR_VERSION..."
curl -L "https://archive.apache.org/dist/solr/solr/$SOLR_VERSION/solr-$SOLR_VERSION.tgz" -o /tmp/solr.tgz
echo "Extracting..."
tar xzf /tmp/solr.tgz -C /tmp
mv "/tmp/solr-$SOLR_VERSION" "$SOLR_DIR"
rm /tmp/solr.tgz

# Create paozier core config
mkdir -p "$SOLR_DIR/server/solr/paozier/conf"
cp scripts/schema.xml "$SOLR_DIR/server/solr/paozier/conf/schema.xml"
cp scripts/solrconfig.xml "$SOLR_DIR/server/solr/paozier/conf/solrconfig.xml"

# Create core.properties
echo "name=paozier" > "$SOLR_DIR/server/solr/paozier/core.properties"

echo "Solr setup complete."
