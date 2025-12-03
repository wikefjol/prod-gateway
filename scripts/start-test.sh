#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "Starting APISIX Test Environment..."
echo "=================================="

# Change to project directory
cd "$PROJECT_DIR"

# Start test services
docker compose -f docker-compose.test.yml up -d

echo ""
echo "Test environment started successfully!"
echo ""
echo "Services available at:"
echo "  - APISIX Gateway:  http://localhost:9081"
echo "  - APISIX Admin:    http://localhost:9181"
echo "  - APISIX Dashboard: Built-in at Admin API (enable_admin_ui: true)"
echo ""
echo "To inspect the test environment:"
echo "  ./apisix-inspect.sh -e test"
echo ""
echo "To view logs:"
echo "  docker compose -f docker-compose.test.yml logs -f"
echo ""
echo "To stop the test environment:"
echo "  ./scripts/stop-env.sh test"
echo ""