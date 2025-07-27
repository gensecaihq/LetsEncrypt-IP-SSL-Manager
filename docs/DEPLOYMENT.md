# Deployment Examples

Real-world deployment scenarios and configurations for the LetsEncrypt IP SSL Manager.

## 📋 Table of Contents

1. [Simple Web Server](#-simple-web-server)
2. [Load Balanced Environment](#-load-balanced-environment)
3. [Container Deployment](#-container-deployment)
4. [Cloud Provider Deployment](#-cloud-provider-deployment)
5. [High Availability Setup](#-high-availability-setup)
6. [Microservices Architecture](#-microservices-architecture)
7. [Reverse Proxy Configuration](#-reverse-proxy-configuration)
8. [Monitoring Integration](#-monitoring-integration)

## 🌐 Simple Web Server

### Scenario: Basic NGINX Web Server

**Environment:**
- Single Ubuntu 22.04 server
- Public IP: 203.0.113.10
- NGINX serving static content
- Basic SSL certificate management

**Installation:**
```bash
# 1. Update system
sudo apt update && sudo apt upgrade -y

# 2. Install NGINX
sudo apt install -y nginx

# 3. Configure firewall
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 80/tcp    # HTTP
sudo ufw allow 443/tcp   # HTTPS
sudo ufw enable

# 4. Clone and setup SSL manager
git clone https://github.com/yourusername/letsencrypt-ip-manager.git
cd letsencrypt-ip-manager
chmod +x letsencrypt-ip-ssl-manager.sh

# 5. Run interactive setup
sudo ./letsencrypt-ip-ssl-manager.sh --setup
```

**NGINX Configuration:**
```nginx
# /etc/nginx/sites-available/default
server {
    listen 80;
    server_name 203.0.113.10;
    
    # Redirect HTTP to HTTPS
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name 203.0.113.10;
    
    # SSL Configuration
    ssl_certificate /etc/letsencrypt/live/203.0.113.10/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/203.0.113.10/privkey.pem;
    
    # Modern SSL settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    
    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options DENY;
    
    # Document root
    root /var/www/html;
    index index.html index.htm;
    
    location / {
        try_files $uri $uri/ =404;
    }
    
    # ACME challenge location
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
}
```

**Deployment Commands:**
```bash
# Generate certificate
sudo ./letsencrypt-ip-ssl-manager.sh -i 203.0.113.10 -e admin@example.com

# Test NGINX configuration
sudo nginx -t

# Restart NGINX
sudo systemctl restart nginx

# Verify SSL
curl -I https://203.0.113.10
```

---

## ⚖️ Load Balanced Environment

### Scenario: Multiple Servers Behind Load Balancer

**Environment:**
- 3 Ubuntu servers behind HAProxy
- Load balancer IP: 203.0.113.10
- Backend servers: 192.168.1.10, 192.168.1.11, 192.168.1.12
- SSL termination at load balancer

**Load Balancer Setup:**

**HAProxy Configuration:**
```
# /etc/haproxy/haproxy.cfg
global
    daemon
    user haproxy
    group haproxy
    ssl-default-bind-ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384
    ssl-default-bind-options ssl-min-ver TLSv1.2 no-sslv3

defaults
    mode http
    timeout connect 5000ms
    timeout client 50000ms
    timeout server 50000ms

frontend web_frontend
    bind 203.0.113.10:80
    bind 203.0.113.10:443 ssl crt /etc/letsencrypt/live/203.0.113.10/fullchain.pem
    
    # Redirect HTTP to HTTPS
    redirect scheme https if !{ ssl_fc }
    
    # ACME challenge handling
    acl acme_challenge path_beg /.well-known/acme-challenge/
    use_backend acme_backend if acme_challenge
    
    default_backend web_servers

backend web_servers
    balance roundrobin
    server web1 192.168.1.10:80 check
    server web2 192.168.1.11:80 check
    server web3 192.168.1.12:80 check

backend acme_backend
    server acme_server 127.0.0.1:8080
```

**Certificate Management:**
```bash
# On load balancer
sudo ./letsencrypt-ip-ssl-manager.sh -i 203.0.113.10 -e admin@example.com -w /var/www/acme

# Setup ACME challenge server
sudo python3 -m http.server 8080 --directory /var/www/acme &

# Reload HAProxy after certificate renewal
echo 'systemctl reload haproxy' | sudo tee /etc/letsencrypt/renewal-hooks/deploy/haproxy-reload
sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/haproxy-reload
```

---

## 🐳 Container Deployment

### Scenario: Docker Container with SSL

**Environment:**
- Docker container running web application
- Host IP: 203.0.113.10
- SSL certificates mounted as volumes
- Automated certificate renewal

**Dockerfile:**
```dockerfile
FROM nginx:alpine

# Copy static content
COPY ./app /usr/share/nginx/html

# Copy NGINX configuration
COPY ./nginx.conf /etc/nginx/nginx.conf

# Create certificate directory
RUN mkdir -p /etc/letsencrypt/live

EXPOSE 80 443

CMD ["nginx", "-g", "daemon off;"]
```

**Docker Compose:**
```yaml
# docker-compose.yml
version: '3.8'

services:
  web:
    build: .
    ports:
      - "203.0.113.10:80:80"
      - "203.0.113.10:443:443"
    volumes:
      - /etc/letsencrypt:/etc/letsencrypt:ro
      - /var/www/html:/var/www/html
    restart: unless-stopped
    
  certbot:
    image: certbot/certbot
    volumes:
      - /etc/letsencrypt:/etc/letsencrypt
      - /var/www/html:/var/www/html
    command: certonly --webroot --webroot-path=/var/www/html -d 203.0.113.10 --email admin@example.com --agree-tos --no-eff-email
```

**Deployment Script:**
```bash
#!/bin/bash
# deploy.sh

# Install SSL manager on host
sudo ./letsencrypt-ip-ssl-manager.sh --setup

# Generate initial certificate
sudo ./letsencrypt-ip-ssl-manager.sh -i 203.0.113.10 -e admin@example.com

# Deploy containers
docker-compose up -d

# Setup renewal hook
echo 'docker-compose restart web' | sudo tee /etc/letsencrypt/renewal-hooks/deploy/docker-reload
sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/docker-reload
```

---

## ☁️ Cloud Provider Deployment

### Scenario: AWS EC2 with Application Load Balancer

**Environment:**
- AWS Application Load Balancer
- Multiple EC2 instances
- Route 53 for DNS
- Auto Scaling Group

**Infrastructure as Code (Terraform):**
```hcl
# main.tf
resource "aws_instance" "web_servers" {
  count           = 3
  ami             = "ami-0c55b159cbfafe1d0"  # Ubuntu 22.04
  instance_type   = "t3.micro"
  key_name        = var.key_pair_name
  subnet_id       = aws_subnet.public[count.index].id
  security_groups = [aws_security_group.web.id]
  
  user_data = <<-EOF
    #!/bin/bash
    apt update && apt upgrade -y
    apt install -y nginx git
    
    # Clone SSL manager
    cd /opt
    git clone https://github.com/yourusername/letsencrypt-ip-manager.git
    cd letsencrypt-ip-manager
    chmod +x letsencrypt-ip-ssl-manager.sh
    
    # Configure nginx
    cat > /etc/nginx/sites-available/default << 'NGINX_EOF'
    server {
        listen 80;
        location / {
            return 200 "Server $(hostname -I)\n";
            add_header Content-Type text/plain;
        }
        location /.well-known/acme-challenge/ {
            root /var/www/html;
        }
    }
NGINX_EOF
    
    systemctl restart nginx
  EOF
  
  tags = {
    Name = "web-server-${count.index + 1}"
  }
}

resource "aws_lb" "main" {
  name               = "main-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets           = aws_subnet.public[*].id
}

resource "aws_lb_target_group" "web" {
  name     = "web-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
  
  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = "/"
    matcher             = "200"
  }
}
```

**Certificate Setup on ALB Instance:**
```bash
# Get ALB public IP
ALB_IP=$(aws elbv2 describe-load-balancers --names main-alb --query 'LoadBalancers[0].DNSName' --output text | nslookup | grep Address | tail -1 | cut -d' ' -f2)

# Setup SSL on one instance for ACME challenges
sudo ./letsencrypt-ip-ssl-manager.sh -i $ALB_IP -e admin@example.com

# Upload certificate to AWS Certificate Manager
aws acm import-certificate \
  --certificate fileb:///etc/letsencrypt/live/$ALB_IP/cert.pem \
  --private-key fileb:///etc/letsencrypt/live/$ALB_IP/privkey.pem \
  --certificate-chain fileb:///etc/letsencrypt/live/$ALB_IP/chain.pem
```

---

## 🔄 High Availability Setup

### Scenario: Multi-Master High Availability

**Environment:**
- 2 primary servers with shared storage
- Floating IP for failover
- Automatic certificate synchronization
- Health monitoring and failover

**Primary Server Setup:**
```bash
# Server 1 (203.0.113.10)
sudo ./letsencrypt-ip-ssl-manager.sh --setup
sudo ./letsencrypt-ip-ssl-manager.sh -i 203.0.113.10 -e admin@example.com

# Setup shared storage (NFS)
sudo apt install -y nfs-kernel-server
echo "/etc/letsencrypt 203.0.113.11(rw,sync,no_subtree_check)" | sudo tee -a /etc/exports
sudo exportfs -a
```

**Secondary Server Setup:**
```bash
# Server 2 (203.0.113.11)
sudo apt install -y nfs-common
sudo mount 203.0.113.10:/etc/letsencrypt /etc/letsencrypt

# Add to fstab for persistent mount
echo "203.0.113.10:/etc/letsencrypt /etc/letsencrypt nfs defaults 0 0" | sudo tee -a /etc/fstab

# Install SSL manager
git clone https://github.com/yourusername/letsencrypt-ip-manager.git
cd letsencrypt-ip-manager
chmod +x letsencrypt-ip-ssl-manager.sh
```

**Keepalived Configuration:**
```bash
# /etc/keepalived/keepalived.conf (Server 1)
vrrp_instance VI_1 {
    state MASTER
    interface eth0
    virtual_router_id 51
    priority 110
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass mypassword
    }
    virtual_ipaddress {
        203.0.113.10
    }
    notify_master "/usr/local/bin/ssl-master-script.sh"
}
```

**Failover Script:**
```bash
#!/bin/bash
# /usr/local/bin/ssl-master-script.sh

# Become SSL certificate master
sudo /opt/letsencrypt-ip-manager/letsencrypt-ip-ssl-manager.sh --status
if [ $? -ne 0 ]; then
    # Try to recover certificates
    sudo /opt/letsencrypt-ip-manager/letsencrypt-ip-ssl-manager.sh --emergency
fi

# Restart web services
sudo systemctl restart nginx
sudo systemctl restart keepalived
```

---

## 🔧 Microservices Architecture

### Scenario: Kubernetes Cluster with Ingress

**Environment:**
- Kubernetes cluster
- NGINX Ingress Controller
- Multiple microservices
- Centralized certificate management

**ConfigMap for SSL Manager:**
```yaml
# ssl-manager-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: ssl-manager-config
  namespace: default
data:
  config.conf: |
    USER_EMAIL="admin@example.com"
    USER_WEBROOT="/var/www/html"
    AUTO_RENEWAL_ENABLED="true"
    LOG_LEVEL="INFO"
```

**SSL Manager Deployment:**
```yaml
# ssl-manager-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ssl-manager
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ssl-manager
  template:
    metadata:
      labels:
        app: ssl-manager
    spec:
      containers:
      - name: ssl-manager
        image: ubuntu:22.04
        command: ["/bin/bash", "-c"]
        args:
          - |
            apt update && apt install -y git curl openssl dnsutils python3 snapd
            git clone https://github.com/yourusername/letsencrypt-ip-manager.git /opt/ssl-manager
            cd /opt/ssl-manager
            chmod +x letsencrypt-ip-ssl-manager.sh
            ./letsencrypt-ip-ssl-manager.sh --install
            while true; do sleep 3600; done
        volumeMounts:
        - name: config
          mountPath: /etc/letsencrypt-ip-manager
        - name: certificates
          mountPath: /etc/letsencrypt
        - name: webroot
          mountPath: /var/www/html
      volumes:
      - name: config
        configMap:
          name: ssl-manager-config
      - name: certificates
        persistentVolumeClaim:
          claimName: ssl-certificates
      - name: webroot
        persistentVolumeClaim:
          claimName: acme-webroot
```

**Ingress Configuration:**
```yaml
# ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-ingress
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
spec:
  tls:
  - hosts:
    - 203.0.113.10
    secretName: ssl-certificate
  rules:
  - host: 203.0.113.10
    http:
      paths:
      - path: /api/users
        pathType: Prefix
        backend:
          service:
            name: user-service
            port:
              number: 80
      - path: /api/orders
        pathType: Prefix
        backend:
          service:
            name: order-service
            port:
              number: 80
      - path: /.well-known/acme-challenge
        pathType: Prefix
        backend:
          service:
            name: ssl-manager-service
            port:
              number: 80
```

---

## 🔄 Reverse Proxy Configuration

### Scenario: Traefik Reverse Proxy

**Environment:**
- Traefik as reverse proxy
- Multiple backend services
- Automatic service discovery
- SSL certificate management

**Traefik Configuration:**
```yaml
# traefik.yml
api:
  dashboard: true
  debug: true

entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
  websecure:
    address: ":443"

providers:
  docker:
    exposedByDefault: false
  file:
    filename: /etc/traefik/dynamic.yml

certificatesResolvers:
  letsencrypt:
    acme:
      tlsChallenge: {}
      email: admin@example.com
      storage: /acme.json
      httpChallenge:
        entryPoint: web
```

**Dynamic Configuration:**
```yaml
# dynamic.yml
http:
  routers:
    api:
      rule: "Host(`203.0.113.10`) && (PathPrefix(`/api`) || PathPrefix(`/dashboard`))"
      service: api@internal
      tls:
        certResolver: letsencrypt
        
  services:
    app:
      loadBalancer:
        servers:
        - url: "http://192.168.1.10:8080"
        - url: "http://192.168.1.11:8080"
```

**Docker Compose with Traefik:**
```yaml
# docker-compose.yml
version: '3.8'

services:
  traefik:
    image: traefik:v2.9
    command:
      - "--configFile=/etc/traefik/traefik.yml"
    ports:
      - "203.0.113.10:80:80"
      - "203.0.113.10:443:443"
      - "8080:8080"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./traefik.yml:/etc/traefik/traefik.yml:ro
      - ./dynamic.yml:/etc/traefik/dynamic.yml:ro
      - ./acme.json:/acme.json
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.dashboard.rule=Host(`203.0.113.10`) && (PathPrefix(`/api`) || PathPrefix(`/dashboard`))"
      - "traefik.http.routers.dashboard.tls=true"
      - "traefik.http.routers.dashboard.tls.certresolver=letsencrypt"

  app:
    image: nginx
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.app.rule=Host(`203.0.113.10`)"
      - "traefik.http.routers.app.tls=true"
      - "traefik.http.routers.app.tls.certresolver=letsencrypt"
```

---

## 📊 Monitoring Integration

### Scenario: Prometheus + Grafana Monitoring

**Environment:**
- Prometheus for metrics collection
- Grafana for visualization
- Alertmanager for notifications
- SSL certificate monitoring

**SSL Certificate Exporter:**
```bash
#!/bin/bash
# /usr/local/bin/ssl-cert-exporter.sh

# SSL certificate metrics for Prometheus
CERT_FILE="/etc/letsencrypt/live/203.0.113.10/cert.pem"
METRICS_FILE="/var/lib/node_exporter/textfile_collector/ssl_certificate.prom"

if [ -f "$CERT_FILE" ]; then
    # Get certificate expiration timestamp
    EXPIRY=$(openssl x509 -in "$CERT_FILE" -noout -enddate | cut -d= -f2)
    EXPIRY_TIMESTAMP=$(date -d "$EXPIRY" +%s)
    
    # Get current timestamp
    NOW=$(date +%s)
    
    # Calculate days until expiration
    DAYS_UNTIL_EXPIRY=$(( (EXPIRY_TIMESTAMP - NOW) / 86400 ))
    
    # Write metrics
    cat > "$METRICS_FILE" << EOF
# HELP ssl_certificate_expiry_days Days until SSL certificate expires
# TYPE ssl_certificate_expiry_days gauge
ssl_certificate_expiry_days{ip="203.0.113.10"} $DAYS_UNTIL_EXPIRY

# HELP ssl_certificate_expiry_timestamp Unix timestamp when SSL certificate expires
# TYPE ssl_certificate_expiry_timestamp gauge
ssl_certificate_expiry_timestamp{ip="203.0.113.10"} $EXPIRY_TIMESTAMP
EOF
else
    # Certificate not found
    cat > "$METRICS_FILE" << EOF
# HELP ssl_certificate_expiry_days Days until SSL certificate expires
# TYPE ssl_certificate_expiry_days gauge
ssl_certificate_expiry_days{ip="203.0.113.10"} -1
EOF
fi
```

**Prometheus Configuration:**
```yaml
# prometheus.yml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'node-exporter'
    static_configs:
      - targets: ['203.0.113.10:9100']
  
  - job_name: 'ssl-certificates'
    scrape_interval: 60s
    static_configs:
      - targets: ['203.0.113.10:9100']

rule_files:
  - "/etc/prometheus/ssl_rules.yml"

alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - alertmanager:9093
```

**Alerting Rules:**
```yaml
# ssl_rules.yml
groups:
  - name: ssl_certificate_alerts
    rules:
      - alert: SSLCertificateExpiringSoon
        expr: ssl_certificate_expiry_days < 2
        for: 1h
        labels:
          severity: warning
        annotations:
          summary: "SSL certificate expiring soon for IP {{ $labels.ip }}"
          description: "SSL certificate for {{ $labels.ip }} expires in {{ $value }} days"
      
      - alert: SSLCertificateExpired
        expr: ssl_certificate_expiry_days < 0
        for: 0m
        labels:
          severity: critical
        annotations:
          summary: "SSL certificate expired for IP {{ $labels.ip }}"
          description: "SSL certificate for {{ $labels.ip }} has expired"
```

**Grafana Dashboard:**
```json
{
  "dashboard": {
    "title": "SSL Certificate Monitoring",
    "panels": [
      {
        "title": "Certificate Expiry Days",
        "type": "stat",
        "targets": [
          {
            "expr": "ssl_certificate_expiry_days",
            "legendFormat": "{{ ip }}"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "thresholds": {
              "steps": [
                {"color": "red", "value": 0},
                {"color": "yellow", "value": 2},
                {"color": "green", "value": 7}
              ]
            }
          }
        }
      }
    ]
  }
}
```

---

## 🚀 Advanced Deployment Patterns

### Blue-Green Deployment

```bash
#!/bin/bash
# blue-green-ssl-deployment.sh

# Blue-Green deployment with SSL certificates
BLUE_IP="203.0.113.10"
GREEN_IP="203.0.113.11"
CURRENT=$(cat /etc/nginx/current_environment)

if [ "$CURRENT" = "blue" ]; then
    NEW_ENV="green"
    NEW_IP="$GREEN_IP"
else
    NEW_ENV="blue"
    NEW_IP="$BLUE_IP"
fi

# Deploy SSL certificate to new environment
sudo ./letsencrypt-ip-ssl-manager.sh -i "$NEW_IP" -e admin@example.com

# Test new environment
curl -f "https://$NEW_IP/health" || exit 1

# Switch traffic
echo "$NEW_ENV" > /etc/nginx/current_environment
sudo systemctl reload nginx

echo "Switched to $NEW_ENV environment ($NEW_IP)"
```

### Canary Deployment

```bash
#!/bin/bash
# canary-ssl-deployment.sh

# Canary deployment with SSL
MAIN_IP="203.0.113.10"
CANARY_IP="203.0.113.11"
CANARY_PERCENT=10

# Setup SSL for both environments
sudo ./letsencrypt-ip-ssl-manager.sh -i "$MAIN_IP" -e admin@example.com
sudo ./letsencrypt-ip-ssl-manager.sh -i "$CANARY_IP" -e admin@example.com

# Configure load balancer for canary
cat > /etc/nginx/nginx.conf << EOF
upstream backend {
    server $MAIN_IP:443 weight=$((100 - CANARY_PERCENT));
    server $CANARY_IP:443 weight=$CANARY_PERCENT;
}

server {
    listen 443 ssl;
    ssl_certificate /etc/letsencrypt/live/$MAIN_IP/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$MAIN_IP/privkey.pem;
    
    location / {
        proxy_pass https://backend;
        proxy_ssl_verify off;
    }
}
EOF

sudo nginx -s reload
```

---

This comprehensive deployment guide covers real-world scenarios from simple single-server setups to complex enterprise architectures. Each example includes complete configuration files and deployment scripts to help you implement SSL certificate management in your specific environment.

For additional deployment scenarios or custom configurations, refer to the [User Manual](USER_MANUAL.md) and [API Reference](API_REFERENCE.md).