# phpMyAdmin Helm chart

Deploys the official phpMyAdmin image with cookie authentication and an unprivileged Apache port.

The chart creates a Deployment, ClusterIP Service, ServiceAccount, and ephemeral session directory. Configure the target MariaDB or MySQL host through `envVars`.

```console
helm install phpmyadmin oci://registry-1.docker.io/wodby/phpmyadmin
```
