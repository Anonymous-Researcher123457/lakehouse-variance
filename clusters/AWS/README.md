## Requirements

The following tools must be installed and available on your `PATH`:

- `kubectl`
- `helm`
- `aws`
- `eksctl`

## Required Configuration Updates

### Trino Image

Update the Trino image reference with your own built image:
`<YOUR_TRINO_IMAGE:TAG>`

Files:
- `./YAML/trino-worker.yaml`
- `./YAML/trino-coord.yaml`

### Trino Client image

Update the Trino client image reference with the built image:
`<YOUR_TRINO_CLIENT_IMAGE:TAG>`   

Files:
- `./YAML/workload.yaml`

### Kubernetes Namespace

Replace the namespace placeholder:
`<YOUR_K8_NAMESPACE>`

Files:
- `./YAML/namespace.yaml`
- `./YAML/trino-sa.yaml`

### AWS Access Key ID

Replace the AWS Access Key ID placeholder:
`<YOUR_AWS_ACCESS_KEY_ID>`

Files:
- `./YAML/core-site-s3a.yaml`
- `./YAML/trino-connector-iceberg-config.yaml`

### AWS Secret Access Key

Replace the AWS Secret Access Key placeholder:
`<YOUR_AWS_SECRET_ACCESS_KEY>`

Files:
- `./YAML/core-site-s3a.yaml`
- `./YAML/trino-connector-iceberg-config.yaml`

### AWS Region

Replace the AWS Region placeholder:

`<REGION>`

Files:
- `./YAML/core-site-s3a.yaml`
- `./YAML/trino-connector-iceberg-config.yaml`
