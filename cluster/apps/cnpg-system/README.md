# Cloud Native PostgreSQL

```bash
kubectl patch cluster cnpg-cluster \
  -n cnpg-system \
  --type merge \
  -p '{
    "spec": {
      "plugins": [
        {
          "name": "barman-cloud.cloudnative-pg.io",
          "isWALArchiver": true,
          "parameters": {
            "barmanObjectName": "aws-object-store"
          }
        }
      ]
    }
  }'

```
