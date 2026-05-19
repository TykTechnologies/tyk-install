# Tyk Install Repository

Tyk deployment configurations for Docker and Kubernetes. All configurations are transparent, documented, follow best practices, and ready to use.

## Prerequisites

**Tyk Licenses** - Get free trial access at [tyk.io/sign-up](https://tyk.io/sign-up/)

Required licenses depend on deployment type:

- **Self-Managed**: Dashboard license, Portal license (optional)
- **Hybrid**: Tyk Cloud account with MDCB credentials
- **Operator**: Operator license

## Quick Start

Choose your deployment:

### Docker

| Deployment       | Description                                                     | Guide                            |
| ---------------- | --------------------------------------------------------------- | -------------------------------- |
| **Self-Managed** | Full stack: Dashboard, Gateway, Portal, Pump, Redis, PostgreSQL | [README](./docker/self-managed/) |
| **Hybrid**       | Data plane connecting to Tyk Cloud/MDCB: Gateway, Pump, Redis   | [README](./docker/hybrid/)       |
| **AI Studio**    | AI Studio, Microgateway, analytics pulse, and PostgreSQL        | [README](./docker/ai-studio/)    |

### Kubernetes (Helm)

| Deployment       | Description                             | Guide                                       |
| ---------------- | --------------------------------------- | ------------------------------------------- |
| **Self-Managed** | Full stack using `tyk-stack` chart      | [README](./kubernetes/helm-self-managed/)   |
| **Hybrid**       | Data plane using `tyk-data-plane` chart | [README](./kubernetes/helm-hybrid/)         |
| **Operator**     | Standalone Tyk Operator                 | [README](./kubernetes/standalone-operator/) |

## Utilities

### Bootstrap Utility

Automated setup for Tyk deployments - creates organization, admin user, test API, policies, and Portal configuration.

| Utility       | Description                                  | Guide                        |
| ------------- | -------------------------------------------- | ---------------------------- |
| **Bootstrap** | Automated org/admin/API/Portal bootstrapping | [README](./utils/bootstrap/) |

### Docker Utilities

Located in `docker/utils/`:

| File                    | Description                                                                       |
| ----------------------- | --------------------------------------------------------------------------------- |
| `dbs.sql`               | PostgreSQL initialization script (creates `tyk_dashboard` and `portal` databases) |
| `crt-generator.sh`      | TLS certificate generator for Gateway and Dashboard                               |
| `GeoLite2-Country.mmdb` | MaxMind GeoIP database for country-level IP analytics                             |

## Repository Structure

```text
tyk-install/
├── docker/
│   ├── self-managed/      # Full stack Docker deployment
│   ├── hybrid/            # Hybrid data plane Docker deployment
│   ├── ai-studio/         # AI Studio Docker deployment
│   └── utils/             # Shared Docker utilities
├── kubernetes/
│   ├── helm-self-managed/ # Full stack Helm deployment
│   ├── helm-hybrid/       # Hybrid data plane Helm deployment
│   └── standalone-operator/ # Tyk Operator deployment
└── utils/
    └── bootstrap/         # Bootstrap automation utility
```

## Resources

- [Free Trial](https://tyk.io/sign-up/)
- [Tyk Documentation](https://tyk.io/docs/)
- [Tyk Helm Charts](https://github.com/TykTechnologies/tyk-charts)
- [Release Notes](https://tyk.io/docs/developer-support/release-notes/overview)
- [Support](https://support.tyk.io/hc/en-gb)
