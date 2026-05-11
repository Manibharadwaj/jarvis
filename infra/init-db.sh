#!/bin/bash
set -euo pipefail

echo "Starting PostgreSQL and Redis..."
docker compose -f docker-compose.yml up -d postgres redis

echo "Waiting for PostgreSQL to be healthy..."
until docker compose exec -T postgres pg_isready -U jarvis; do
  sleep 1
done

echo "Database ready. Run 'npm run dev' from backend/ to apply migrations."

echo ""
echo "Quick commands:"
echo "  Connect to DB:  docker compose exec postgres psql -U jarvis jarvis"
echo "  Redis CLI:      docker compose exec redis redis-cli"
echo "  Check logs:     docker compose logs -f"
