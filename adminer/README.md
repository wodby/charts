# Adminer Helm chart

Deploys the Wodby Adminer image as a single-replica database administration interface.

The chart creates a Deployment, ClusterIP Service, and ServiceAccount. Database connection defaults are supplied through `envVars`; credentials remain user-entered in Adminer.

```console
helm install adminer oci://registry-1.docker.io/wodby/adminer
```
