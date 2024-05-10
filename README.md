# Helm Charts

```
helm package php-fpm
helm package nginx
helm package nfs-provisioner
helm package mariadb
```

```
helm push nfs-provisioner-0.1.2.tgz oci://registry-1.docker.io/wodby
helm push php-fpm-0.1.2.tgz oci://registry-1.docker.io/wodby
helm push nginx-0.1.0.tgz oci://registry-1.docker.io/wodby
helm push mariadb-0.1.0.tgz oci://registry-1.docker.io/wodby
```
