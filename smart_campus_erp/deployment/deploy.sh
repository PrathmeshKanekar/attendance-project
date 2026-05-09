#!/bin/bash
set -e

echo "━━━ Smart Campus ERP Deployment Script ━━━"

APP_DIR="/opt/smart_campus"
BACKEND_DIR="$APP_DIR/backend"
VENV_DIR="$APP_DIR/venv"

# Activate virtualenv
source $VENV_DIR/bin/activate

# Pull latest code (if using git)
# cd $APP_DIR && git pull origin main

# Install/update dependencies
pip install -r $BACKEND_DIR/requirements.txt --quiet

# Collect static files
cd $BACKEND_DIR
python manage.py collectstatic --no-input

# Run migrations
python manage.py migrate --no-input

# Check for issues
python manage.py check --deploy

# Restart service
sudo systemctl restart smart_campus
sudo systemctl status smart_campus --no-pager

echo "✅ Deployment complete!"
