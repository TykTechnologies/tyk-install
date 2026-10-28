# Tyk Install Repository

Tyk deployment configurations for Docker, Kubernetes, and bare metal. All configurations are transparent, documented, follow best practices, and ready to use. The repository is also an [Agent Plugin](https://agent-plugins.org), so an AI coding agent can [deploy and verify Tyk from it](#deploy-with-an-ai-coding-agent).

## Prerequisites

**Open source vs paid** - Tyk Gateway and Tyk Pump are open source (MPL 2.0) and need no license. Tyk Dashboard, Tyk Developer Portal, Tyk Operator and Tyk Multi Data Center Bridge (MDCB) need a license key: request one with a [Tyk Self-Managed trial](https://tyk.io/self-managed-trial/) (the key arrives by email). For a hosted control plane, [create a Tyk Cloud account](https://tyk.io/docs/getting-started/create-account). The canonical comparison is [Tyk deployment options and licensing](https://tyk.io/docs/apim).

To run only the open source Gateway, use [`docker/oss/`](./docker/oss/) or [`kubernetes/helm-oss/`](./kubernetes/helm-oss/) here, or the two-minute [Tyk Open Source Gateway quick start](https://tyk.io/docs/deployment-and-operations/tyk-open-source-api-gateway/quick-start).

Required licenses depend on deployment type:

- **OSS**: none
- **Self-Managed**: Dashboard license, Portal license (optional)
- **Hybrid**: Tyk Cloud account with MDCB credentials
- **MDCB**: Dashboard license and MDCB license
- **Operator**: Operator license
- **AI Studio**: none for Community Edition, AI license for Enterprise Edition

## Quick Start

The fastest way to try Tyk Self-Managed is the Getting Started deployment. It starts the full stack and preloads sample APIs, policies and a configured Developer Portal:

```bash
git clone https://github.com/TykTechnologies/tyk-install
cd tyk-install/docker/self-managed
cp .env.example .env   # set TYK_LICENSE_KEY and TYK_PORTAL_LICENSE
cd ../getting-started
bash start.sh
```

Log in to Tyk Dashboard at `http://localhost:3000` with `developer@tyk.io` / `specialpassword`. For the full walkthrough, see the [Tyk Self-Managed quick start](https://tyk.io/docs/getting-started/quick-start).

Or choose a deployment:

### Docker

| Deployment       | Description                                                     | Guide                            |
| ---------------- | --------------------------------------------------------------- | -------------------------------- |
| **OSS**          | Open source Gateway and Redis. No license, no Dashboard         | [README](./docker/oss/)          |
| **Getting Started** | Self-Managed stack with sample APIs, policies and Portal content (`start.sh`) | [Quick start](https://tyk.io/docs/getting-started/quick-start) |
| **Self-Managed** | Full stack: Dashboard, Gateway, Portal, Pump, Redis, PostgreSQL | [README](./docker/self-managed/) |
| **Hybrid**       | Data plane connecting to Tyk Cloud/MDCB: Gateway, Pump, Redis   | [README](./docker/hybrid/)       |
| **MDCB**         | Self-managed control plane plus remote data planes              | [README](./docker/mdcb/)         |
| **AI Studio**    | AI Studio 2.2, Edge Gateway, analytics pulse, and PostgreSQL    | [README](./docker/ai-studio/)    |

### Kubernetes (Helm)

| Deployment       | Description                             | Guide                                       |
| ---------------- | --------------------------------------- | ------------------------------------------- |
| **OSS**          | Open source Gateway using `tyk-oss` chart | [README](./kubernetes/helm-oss/)          |
| **Self-Managed** | Full stack using `tyk-stack` chart      | [README](./kubernetes/helm-self-managed/)   |
| **Hybrid**       | Data plane using `tyk-data-plane` chart | [README](./kubernetes/helm-hybrid/)         |
| **MDCB**         | `tyk-control-plane` and `tyk-data-plane` charts | [README](./kubernetes/helm-mdcb/)   |
| **AI Studio**    | AI Studio 2.2, Edge Gateway, PostgreSQL | [README](./kubernetes/helm-ai-studio/)      |
| **Operator**     | Standalone Tyk Operator                 | [README](./kubernetes/standalone-operator/) |

Self-Managed and Hybrid both run on Red Hat OpenShift from tyk-charts 5.4.0 by layering their
`values-openshift.yaml` overlay. See each guide's "Deploying on Red Hat OpenShift" section.

### Bare metal / VMs

| Deployment  | Description                                                                                     | Guide                  |
| ----------- | ----------------------------------------------------------------------------------------------- | ---------------------- |
| **Gateway** | rpm/deb packages with systemd, no containers. Dashboard and Pump are supported but less tested | [README](./baremetal/) |

### Observability (Optional)

OpenTelemetry traces, metrics and logs for Self-Managed and Hybrid, with an OpenTelemetry Collector,
Prometheus, Alertmanager, Tempo, Loki and Grafana. Ten Grafana dashboards and 47 alert rules cover the
Gateway, Dashboard, MDCB and Developer Portal, and the collector can also send to another backend.

| Platform   | Description                                                                 | Guide                                     |
| ---------- | --------------------------------------------------------------------------- | ----------------------------------------- |
| **Docker** | `docker-compose.otel.yml` overlay for Self-Managed and Hybrid               | [README](./docker/observability/)         |
| **Kubernetes** | Helm values, `values-otel.yaml` overlays and a post-renderer            | [README](./kubernetes/observability/)     |
| **Shared** | Dashboards, alert rules, collector config and component settings            | [README](./observability/)                |

## Deploy with an AI coding agent

This repository is an [Agent Plugin](https://agent-plugins.org) (specification 1.0.0): cloning it
is the install. Open the clone with Claude Code, Codex, or any conformant agent and ask for what
you need, for example "deploy Tyk OSS locally", "install the self-managed stack on my cluster" or
"is this values.yaml production ready?". The agent reads [AGENTS.md](AGENTS.md) and the skills
under `skills/`:

| Skill | What it does |
| --- | --- |
| `tyk-deployment-planner` | Picks a topology from the [topology matrix](./skills/tyk-deployment-planner/references/topology-matrix.md), checks prerequisites, writes a deployment plan. Applies nothing. |
| `tyk-deployment-runner` | Deploys, bootstraps, and verifies with a request through the gateway rather than container status. |
| `tyk-production-readiness` | Audits a config against the production guidance in these files and can generate the OpenShift overlay. |

To use the skills from any directory, run `./install-plugin.sh --engine claude` (or `codex`, or
`both`). The production, performance, security and OpenShift guidance lives as marker comments
beside the settings it applies to (`# PROD:`, `# PROD/PERFORMANCE:`, `# SECURITY:`,
`# Required for deploying on RedHat OpenShift`), and one script reads them so the advice cannot
drift from the configuration:

```bash
python3 skills/tyk-production-readiness/scripts/profiles.py \
  audit kubernetes/helm-self-managed/values.yaml --profile prod --profile security
```

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
├── plugin.json            # Agent Plugins 1.0.0 manifest; this root is the plugin root
├── AGENTS.md              # The agent contract
├── install-plugin.sh      # Optional: link the skills into an agent skills directory
├── skills/                # Agent skills: deployment planner, deployment runner, production readiness
├── baremetal/             # rpm/deb packages plus systemd
├── docker/
│   ├── oss/               # Open source Gateway and Redis, no license
│   ├── self-managed/      # Full stack Docker deployment
│   ├── getting-started/   # Self-Managed plus sample APIs and Portal content (start.sh)
│   ├── hybrid/            # Hybrid data plane Docker deployment
│   ├── mdcb/              # Self-managed control plane and data plane
│   ├── ai-studio/         # AI Studio Docker deployment
│   ├── observability/     # Optional observability stack (docker-compose.otel.yml overlays)
│   └── utils/             # Shared Docker utilities
├── kubernetes/
│   ├── helm-oss/          # Open source Gateway Helm deployment
│   ├── helm-self-managed/ # Full stack Helm deployment
│   ├── helm-hybrid/       # Hybrid data plane Helm deployment
│   ├── helm-mdcb/         # Control plane and data plane Helm values
│   ├── helm-ai-studio/    # AI Studio Helm deployment
│   ├── observability/     # Optional observability stack (Helm values, post-renderer)
│   └── standalone-operator/ # Tyk Operator deployment
├── observability/         # Dashboards, alert rules and collector config for both platforms
└── utils/
    └── bootstrap/         # Bootstrap automation utility
```

## Resources

- [Tyk Self-Managed Trial](https://tyk.io/self-managed-trial/)
- [Tyk deployment options and licensing](https://tyk.io/docs/apim)
- [Tyk Documentation](https://tyk.io/docs/)
- [Tyk Helm Charts](https://github.com/TykTechnologies/tyk-charts)
- [Release Notes](https://tyk.io/docs/developer-support/release-notes/overview)
- [Support](https://support.tyk.io/hc/en-gb)
