# Architecture Diagram (Google Cloud Platform)

```
                                    ┌─────────────────────┐
                                    │   Internet Users    │
                                    └──────────┬──────────┘
                                               │
                                    ┌──────────▼──────────┐
                                    │  Cloud Load Balancer│
                                    │   (HTTPS/HTTP)      │
                                    └──────────┬──────────┘
                                               │
                        ┌──────────────────────┼──────────────────────┐
                        │                      │                      │
                ┌───────▼────────┐    ┌───────▼────────┐    ┌───────▼────────┐
                │ Compute Engine │    │ Compute Engine │    │ Compute Engine │
                │   Instance 1   │    │   Instance 2   │    │   Instance N   │
                │                │    │                │    │                │
                │  ┌──────────┐  │    │  ┌──────────┐  │    │  ┌──────────┐  │
                │  │  Nginx   │  │    │  │  Nginx   │  │    │  │  Nginx   │  │
                │  └────┬─────┘  │    │  └────┬─────┘  │    │  └────┬─────┘  │
                │       │        │    │       │        │    │       │        │
                │  ┌────▼─────┐  │    │  ┌────▼─────┐  │    │  ┌────▼─────┐  │
                │  │   Web    │  │    │  │   Web    │  │    │  │   Web    │  │
                │  │   API    │  │    │  │   API    │  │    │  │   API    │  │
                │  │  Worker  │  │    │  │  Worker  │  │    │  │  Worker  │  │
                │  │ Sandbox  │  │    │  │ Sandbox  │  │    │  │ Sandbox  │  │
                │  │  Plugin  │  │    │  │  Plugin  │  │    │  │  Plugin  │  │
                │  │   SSRF   │  │    │  │   SSRF   │  │    │  │   SSRF   │  │
                │  └──────────┘  │    │  └──────────┘  │    │  └──────────┘  │
                └────────┬───────┘    └────────┬───────┘    └────────┬───────┘
                         │                     │                     │
                         └──────────┬──────────┴──────────┬──────────┘
                                    │                     │
                         ┌──────────▼──────────┐ ┌───────▼────────┐
                         │  VPC Network        │ │  Cloud NAT     │
                         │  (Private Subnet)   │ │  (Internet)    │
                         └──────────┬──────────┘ └────────────────┘
                                    │
        ┌───────────────────────────┼───────────────────────────┐
        │                           │                           │
┌───────▼─────────┐       ┌─────────▼────────┐      ┌──────────▼──────────┐
│   Cloud SQL     │       │  Cloud SQL       │      │   Memorystore       │
│  (PostgreSQL)   │       │  (PostgreSQL     │      │   for Redis         │
│  Main Database  │       │   with pgvector) │      │                     │
│                 │       │  Vector Database │      │  Cache & Broker     │
└─────────────────┘       └──────────────────┘      └─────────────────────┘

                          ┌──────────────────────┐
                          │   Cloud Storage      │
                          │   (File Storage)     │
                          └──────────────────────┘

                          ┌──────────────────────┐
                          │   Cloud Logging      │
                          │   Cloud Monitoring   │
                          └──────────────────────┘
```

## Component Details

### Frontend Layer
- **Cloud Load Balancer**: Global HTTP(S) load balancer distributing traffic across instances
  - Health checks on `/health` endpoint
  - Session affinity (CLIENT_IP)
  - SSL termination (optional)

### Application Layer (Compute Engine)
Each instance runs Docker Compose with the following services:
- **nginx**: Reverse proxy routing requests to api/web
- **web**: Next.js frontend application
- **api**: Flask API server
- **worker**: Celery worker for background tasks
- **worker_beat**: Celery beat for scheduled tasks
- **sandbox**: Code execution environment
- **plugin_daemon**: Plugin management service
- **ssrf_proxy**: Squid proxy for SSRF protection

### Data Layer (Managed Services)
- **Cloud SQL (Main)**: PostgreSQL 15 for application metadata
  - Regional availability for HA
  - Automated backups with PITR
  - Private IP connectivity

- **Cloud SQL (Vector)**: PostgreSQL 15 with pgvector extension
  - Vector similarity search
  - Regional availability for HA
  - Automated backups with PITR

- **Memorystore for Redis**: In-memory cache and message broker
  - Standard HA tier for production
  - Auth enabled for security
  - Used for session storage and Celery

- **Cloud Storage**: Object storage for files
  - Versioning enabled
  - Uniform bucket-level access
  - Service account authentication

### Network Layer
- **VPC Network**: Isolated network for all resources
- **Private Subnet**: Internal IP addresses for instances
- **Cloud NAT**: Outbound internet access for instances
- **Firewall Rules**: 
  - Allow internal communication
  - Allow LB health checks
  - Restrict SSH access

### High Availability Features
- **Multi-Zone Deployment**: Instances distributed across zones
- **Auto-Healing**: Unhealthy instances automatically replaced
- **Auto-Scaling**: Dynamic instance count based on CPU
- **Database Replication**: Regional Cloud SQL with automatic failover
- **Redis HA**: Standard tier with automatic failover

### Security Features
- **Private IP**: Database and Redis accessible only within VPC
- **Service Accounts**: Least-privilege IAM roles
- **Firewall Rules**: Network-level access control
- **Deletion Protection**: Prevents accidental data loss
- **Encrypted Storage**: All data encrypted at rest
- **VPC Peering**: Secure connection to Cloud SQL

### Monitoring and Logging
- **Cloud Logging**: Centralized log management
- **Cloud Monitoring**: Metrics and alerting
- **Health Checks**: Continuous availability monitoring
- **Audit Logs**: Track all infrastructure changes
