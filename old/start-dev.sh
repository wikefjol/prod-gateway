#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "Starting APISIX Development Environment..."
echo "================================="

# Change to project directory
cd "$PROJECT_DIR"

# Start development services
docker compose -f docker-compose.dev.yml up -d

echo ""
echo "Development environment started successfully!"
echo ""
echo "Services available at:"
echo "  - APISIX Gateway:  http://localhost:9080"
echo "  - APISIX Admin:    http://localhost:9180"
echo "  - APISIX Dashboard: Built-in at Admin API (enable_admin_ui: true)"
echo ""
echo "To inspect the development environment:"
echo "  ./apisix-inspect.sh -e dev"
echo ""
echo "To view logs:"
echo "  docker compose -f docker-compose.dev.yml logs -f"
echo ""
echo "To stop the development environment:"
echo "  ./scripts/stop-env.sh dev"
echo ""