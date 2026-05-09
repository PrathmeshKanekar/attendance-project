# Smart Campus ERP — Server Setup Guide

## Prerequisites
- Ubuntu 22.04 LTS
- Python 3.11
- PostgreSQL 15
- Nginx

## Installation Steps

### 1. Server preparation
```bash
sudo apt update && sudo apt upgrade -y
sudo apt install python3.11 python3.11-venv python3-pip \
    postgresql nginx git cmake libopenblas-dev -y
```

### 2. Create app directory
```bash
sudo mkdir -p /opt/smart_campus
sudo chown ubuntu:ubuntu /opt/smart_campus
```

### 3. Clone/upload code
```bash
cd /opt/smart_campus
# Upload your project files here
```

### 4. Setup Python virtualenv
```bash
python3.11 -m venv venv
source venv/bin/activate
pip install -r backend/requirements.txt
```

### 5. Setup PostgreSQL
```bash
sudo -u postgres psql
CREATE DATABASE smart_campus_db;
CREATE USER smart_campus_user WITH PASSWORD 'your_strong_password';
GRANT ALL PRIVILEGES ON DATABASE smart_campus_db TO smart_campus_user;
\q
```

### 6. Configure environment
```bash
cp backend/.env.example .env
nano .env  # edit with real values
```

### 7. Run migrations and seed
```bash
cd backend
python manage.py migrate
python manage.py seed_data
python manage.py createsuperuser
```

### 8. Install systemd service
```bash
sudo cp deployment/smart_campus.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable smart_campus
sudo systemctl start smart_campus
```

### 9. Configure Nginx
```bash
sudo cp deployment/nginx.conf /etc/nginx/sites-available/smart_campus
sudo ln -s /etc/nginx/sites-available/smart_campus \
    /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl restart nginx
```

### 10. Setup daily backup
```bash
chmod +x deployment/backup.sh
crontab -e
# Add: 0 2 * * * /opt/smart_campus/deployment/backup.sh
```
