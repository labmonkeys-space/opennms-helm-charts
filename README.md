[![lint and test](https://github.com/labmonkeys-space/opennms-helm-charts/actions/workflows/lint-and-test.yaml/badge.svg?branch=main)](https://github.com/labmonkeys-space/opennms-helm-charts/actions/workflows/lint-and-test.yaml)

## 🚀 Helm Charts for OpenNMS Horizon

This is an unofficial collection of Helm charts to deploy [OpenNMS Horizon](https://www.opennms.com/en/horizon/) on Kubernetes.
By default, OpenNMS Horizon 34.1.0 will be installed.

### 📦 Available Charts
- [opennms-core](charts/core/README.md): The OpenNMS Horizon Core application.
- [opennms-minion](charts/minion/README.md): OpenNMS Horizon Minion for monitoring in distributed environments.

OpenNMS Horizon requires a PostgreSQL database.
For a production deployment, it is recommended to use a managed PostgreSQL service or a dedicated PostgreSQL chart.
For testing and development purposes, you can use the following chart provided in the develop directory:

- [postgresql](develop/charts/postgresql/README.md): A simple PostgreSQL chart for testing purposes.

### 👮 Prerequisites

- Kubernetes 1.20+
- Helm 3.5+
- A running PostgreSQL instance (for production use, consider using a managed service or a dedicated chart)
- Persistent Volume support in the Kubernetes cluster
- kind (Kubernetes in Docker) for local development and testing

### 🕹️ Local Development

Set up a local Kubernetes cluster using [Kind](https://kind.sigs.k8s.io/) and install the PostgreSQL chart for testing:
```bash
make install-postgres
```

Install the OpenNMS Horizon Core chart:
```bash
helm install my-opennms-core charts/core
```
### 👩‍🔬 Linting and Testing

Run linting and tests for the charts:
```bash
make lint
```

Run installation tests
```bash
make test-install
```

Show rendered templates for a chart in the build directory
```bash
make render-core
```

### 👩‍🏫 Update README

```
make readme
```

### 🧼 Clean up

Deletes build artifacts and delete kind cluster
```bash
make clean
```