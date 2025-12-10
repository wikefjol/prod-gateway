#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "Starting Both APISIX Environments..."
echo "==================================="

# Change to project directory
cd "$PROJECT_DIR"

echo "Starting development environment..."
docker compose -f docker-compose.dev.yml up -d

echo "Starting test environment..."
docker compose -f docker-compose.test.yml up -d

echo ""
echo "Both environments started successfully!"
echo ""
echo "Development Environment:"
echo "  - APISIX Gateway:  http://localhost:9080"
echo "  - APISIX Admin:    http://localhost:9180"
echo "  - APISIX Dashboard: Built-in at Admin API"
echo ""
echo "Test Environment:"
echo "  - APISIX Gateway:  http://localhost:9081"
echo "  - APISIX Admin:    http://localhost:9181"
echo "  - APISIX Dashboard: Built-in at Admin API"
echo ""
echo "To inspect environments:"
echo "  ./apisix-inspect.sh -e dev   # Development"
echo "  ./apisix-inspect.sh -e test  # Test"
echo ""
echo "To view logs:"
echo "  docker compose -f docker-compose.dev.yml logs -f   # Dev logs"
echo "  docker compose -f docker-compose.test.yml logs -f  # Test logs"
echo ""
echo "To stop environments:"
echo "  ./scripts/stop-env.sh both"
echo ""