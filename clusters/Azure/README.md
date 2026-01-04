requirements
az
helm
kubectl

## Required Configuration Updates

### Trino Image

Update the Trino image reference with your own built image:
`<YOUR_TRINO_IMAGE:TAG>`

Files:
- `trino-worker.yaml`
- `trino-coord.yaml`


<CONTAINER>
core-site-config.yaml

<STORAGE_ACCOUNT>
core-site-config.yaml

<ABFS_ACCESS_KEY>
core-site-config.yaml
trino-connector-iceberg-config.yaml

### Kubernetes Namespace

Replace the namespace placeholder:

`<NAMESPACE>`

Files:
- `namespace.yaml`
- 