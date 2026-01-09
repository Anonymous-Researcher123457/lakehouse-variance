## Clusters

This directory contains cluster-specific deployment scripts and configuration required to provision and run Trino-based experiments across different execution environments.

Each subdirectory corresponds to a distinct infrastructure platform (e.g., AWS, Azure, GCP, Local), and encapsulates all logic required to:

- Provision the cluster
- Launch Trino services
- Deploy monitoring components
- Execute workloads
- Tear down resources

The tooling in this directory is intentionally platform-specific, reflecting the practical differences between cloud providers and local deployments.

---

### Content

Each cluster directory (e.g., `AWS/`, `Azure/`, `GCP/`, `Local/`) typically contains:

- **YAML/**  
  Infrastructure or Kubernetes manifests used to configure services.

- **Environment configuration**  
  Files such as `.env` or platform-specific credential templates.

- **Cluster lifecycle scripts**  
  - `launch_cluster.sh` – provisions compute resources
  - `delete_cluster.sh` – tears down the cluster
  - `wait.sh` – blocks until services are ready

- **Trino management scripts**  
  - `launch_trino.sh` – deploys the Trino service
  - `delete_trino.sh` – removes the Trino deployment

- **Workload orchestration scripts**  
  - `launch_workload.sh` – triggers execution of query workloads

- **README.md**  
  Platform-specific instructions and prerequisites.


