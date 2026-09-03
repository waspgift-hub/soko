# Soko Vibe Production Deployment

This document contains the complete deployment guide for Soko Vibe's production infrastructure.

## Architecture

```
INTERNET -> CLOUDFLARE EDGE (DNS + WAF + TLS)
              |
              v
       api.soko-vibe.co.tz
              |
              v
       NGINX (reverse proxy + TLS)
              |
              v
   +----------+-----------+
   |       API (Node.js)  |
   |    Port 3000         |
   +----------+-----------+
              |
        +-----+-----+
        |           |
        v           v
   PostgreSQL    Redis
   Port 5432    Port 6379
        |
        v
   Background Worker
     (BullMQ + Sharp + FFmpeg)
```

## Domains

| Domain | Purpose | Target |
|--------|---------|--------|
| `soko-vibe.co.tz` | Public website / landing | Cloudflare Pages / Landing |
| `api.soko-vibe.co.tz` | Node.js API | Nginx -> API container |
| `media.soko-vibe.co.tz` | Media CDN | Cloudflare -> R2 |
| `admin.soko-vibe.co.tz` | Admin panel | Nginx -> Admin container |

## Initial Server Setup (Ubuntu 22.04 LTS)

### 1. Harden SSH

```bash
# As root
adduser deploy
usermod -aG sudo deploy

# Set up SSH keys for deploy user
mkdir -p /home/deploy/.ssh
echo "ssh-rsa YOUR_PUBLIC_KEY" > /home/deploy/.ssh/authorized_keys
chown -R deploy:deploy /home/deploy/.ssh
chmod 700 /home/deploy/.ssh
chmod 600 /home/deploy/.ssh/authorized_keys

# Disable password auth
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl restart ssh

# Set up firewall
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw enable
```

### 2. Install Docker

```bash
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
```

### 3. Install Docker Compose (v2)

```bash
DOCKER_CONFIG=${DOCKER_CONFIG:-$HOME/.docker}
mkdir -p $DOCKER_CONFIG/cli-plugins
curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 -o $DOCKER_CONFIG/cli-plugins/docker-compose
chmod +x $DOCKER_CONFIG/cli-plugins/docker-compose
```

### 4. Deploy Application

```bash
# Clone repository
git clone https://github.com/your-repo/soko-vibe.git /opt/sokovibe

# Copy environment file
cd /opt/sokovibe
cp .env.production .env

# Fill in all environment variables
nano .env

# Start services
docker compose up -d --build
```

## TLS Certificates (Let's Encrypt)

```bash
# Install certbot
snap install core; snap refresh core
snap install --classic certbot
ln -s /snap/bin/certbot /usr/bin/certbot

# Get certificates
certbot certonly --standalone -d api.soko-vibe.co.tz -d admin.soko-vibe.co.tz

# Set up auto-renewal
certbot renew --dry-run
```

## Cloudflare Configuration

### DNS Records
| Type | Name | Value | Proxy |
|------|------|-------|-------|
| A | api | VPS_IP | Proxied |
| A | admin | VPS_IP | Proxied |
| CNAME | media | media.ACCOUNT_ID.r2.cloudflarestorage.com | Proxied |

### R2 Buckets
1. Create in Cloudflare Dashboard: Images, Videos, Thumbnails, Backups
2. Set `media.soko-vibe.co.tz` as custom domain for public buckets
3. Get Access Keys for S3-compatible API

### WAF Rules
- Block SQL injection (Cloudflare managed)
- Block XSS (Cloudflare managed)
- Rate limit API endpoint
- Challenge known botnets

## Backup Strategy

### Cron Job
```bash
# Edit crontab
crontab -e

# Daily backup at 2:00 AM
0 2 * * * /opt/sokovibe/deploy/scripts/backup.sh >> /var/log/sokovibe-backup.log 2>&1

# Weekly full backup Sunday at 3:00 AM
0 3 * * 0 /opt/sokovibe/deploy/scripts/backup.sh weekly >> /var/log/sokovibe-backup.log 2>&1
```

### Retention
- 7 daily backups
- 4 weekly backups
- 3 monthly backups
- All stored in `backups/postgres/` on R2

## Scaling Path

### Stage 1: Launch (0-1000 users)
- 1 VPS (2GB RAM)
- All services on one VPS
- PostgreSQL + Redis + API + Worker

### Stage 2: Growth (1000-10000 users)
- Separate worker from API
- Add Redis persistence
- Optimize PostgreSQL indexes

### Stage 3: High Traffic (10000+ users)
- Multiple API instances behind LB
- Read replicas for PostgreSQL
- Dedicated transcoding workers
- Managed PostgreSQL

## Monitoring

### Health Check
```
GET /health
```
Returns status, database, redis, and memory health.

### Alerts (via UptimeRobot or similar)
- Poll `https://api.soko-vibe.co.tz/health` every 5 minutes
- Alert on 503 status

## Database Schema & Migrations

The Postgres schema (source of truth) is defined in `deploy/postgres/init.sql`,
which is mounted into the Postgres container via `/docker-entrypoint-initdb.d`
and applied automatically on first database initialization.

- The Prisma schema at `soko_langu/server/prisma/schema.prisma` is kept in sync
  with `init.sql`; the Prisma client is generated at build time for the ORM.
- To apply schema changes on an existing database, either rerun the relevant
  `ALTER`/`CREATE` statements from `init.sql` against Postgres, or use
  `prisma migrate deploy` from the server directory.
- The `worker`, `api`, and `nginx` services are all defined in `docker-compose.yml`.

## Running Tests

From the server directory (`soko_langu/server`):

```bash
npm test        # deterministic unit + integration tests (no live env needed)
npm run test:e2e # opt-in live end-to-end tests against a running deployment
```

## Rollback Procedure

1. `git log --oneline` to see previous versions
2. `./deploy.sh <previous-commit>`
3. Monitor health for 15 minutes
4. If rollback also fails, restore from backup
