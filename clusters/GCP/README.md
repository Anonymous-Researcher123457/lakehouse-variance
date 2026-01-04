## Requirements

The following tools must be installed and available on your `PATH`:

- `kubectl`
- `helm` 
- `gcloud` 
- `jq`

## Required Configuration Updates

### Trino Image

Update the Trino image reference with your own built image:
`<YOUR_TRINO_IMAGE:TAG>`

Files:
- `trino-worker.yaml`
- `trino-coord.yaml`

### Kubernetes Namespace

Replace the namespace placeholder:

`<YOUR_K8_NAMESPACE>`

Files:
- `namespace.yaml`

### GCP Service Account Configuration (hive-sa.yaml, trino-sa.yaml)

When deploying on Google Kubernetes Engine (GKE), both the Hive metastore and
Trino require access to Google Cloud Storage. This repository uses GKE
Workload Identity to grant this access.

Before applying `./YAML/hive-sa.yaml` and `./YAML/trino-sa.yaml`, you **must** update the following field:

`
iam.gke.io/gcp-service-account: YOUR_GCP_SERVICE_ACCOUNT_EMAIL
`

Replace this value with the email address of a GCP IAM service account in your
project that has appropriate permissions (e.g. access to the GCS buckets used by
the lakehouse).

### GCP Service Account Key Secret (secrets.yaml)

In order for, the Hive metastore service to access GS buckets, an explicit GCP service account
key file is required. This repository provides a template
Secret manifest for this purpose.

Before applying `./YAML/secrets.yaml`, you **must** update the following field:

`
SA_keyfile.json: BASE64_ENCODED_GCP_SERVICE_ACCOUNT_KEY
`

Replace this value with the base64-encoded contents of your GCP service
account key JSON file.

To generate the value:
`
base64 -w 0 path/to/service-account-key.json
`