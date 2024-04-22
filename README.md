# Helm Charts

```
helm package php-fpm
helm package nfs-provisioner
```

```
helm push php-fpm-0.1.2.tgz oci://registry-1.docker.io/wodby
helm push nfs-provisioner-0.1.2.tgz oci://registry-1.docker.io/wodby
```
