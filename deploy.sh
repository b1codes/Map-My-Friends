#!/bin/bash

# Exit on error
set -e

echo "🚀 Starting redeployment..."

# 1. Pull latest changes (optional, assumes git is set up on EC2)
# git pull origin main

# 2. Build and restart containers
echo "📦 Rebuilding and restarting containers..."
docker compose -f docker-compose.prod.yml up -d --build

# 3. Run database migrations
echo "🗄️ Running database migrations..."
docker compose -f docker-compose.prod.yml exec api python manage.py migrate --noinput

# 4. (Optional) Create a superuser if it's a first-time setup
# echo "👤 Checking for superuser..."
# docker compose -f docker-compose.prod.yml exec api python manage.py shell -c "from django.contrib.auth import get_user_model; User = get_user_model(); User.objects.filter(username='admin').exists() or User.objects.create_superuser('admin', 'admin@example.com', 'password')"

# 5. Clean up unused images to save disk space (Crucial for EC2)
echo "🧹 Cleaning up old Docker images..."
docker image prune -f

echo "✅ Redeployment complete!"
