# Helm Charts

```
helm package cluster-agent
helm package node-agent
helm package node-exporter
helm package php-fpm
helm package nfs-provisioner
```

```
helm push cluster-agent-0.1.2.tgz oci://registry-1.docker.io/wodby
helm push node-agent-0.1.2.tgz oci://registry-1.docker.io/wodby
helm push node-exporter-0.1.2.tgz oci://registry-1.docker.io/wodby
helm push php-fpm-0.1.2.tgz oci://registry-1.docker.io/wodby
helm push nfs-provisioner-0.1.2.tgz oci://registry-1.docker.io/wodby
```
