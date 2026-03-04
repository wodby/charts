# Helm Charts

These charts are designed to be used for deployment with Wodby [services](https://github.com/wodby/services) and may not be generic enough to be used fully independently.

Some functionality like certificates, certain config maps and network policies handled directly by Wodby without helm manifests.

| Chart           | Image                                      | Version |
|-----------------|--------------------------------------------|---------|
| common          |                                            | 1.0.0   |
| gotenberg       | gotenberg/gotenberg                        | 0.1.0   |
| httpd           | wodby/apache                               | 0.2.0   |
| mailpit         | axllent/mailpit                            | 0.2.0   |
| mariadb         | wodby/mariadb                              | 0.2.0   |
| nfs-provisioner | k8s.gcr.io/nfs-subdir-external-provisioner | 0.2.0   |
| nginx           | wodby/nginx                                | 0.2.0   |
| node            | wodby/node                                 | 0.2.0   |
| openclaw        | wodby/openclaw                             | 0.1.0   |
| opensmtpd       | wodby/opensmtpd                            | 0.3.0   |
| php-fpm         | wodby/php                                  | 0.2.0   |
| postgres        | wodby/postgres                             | 0.2.0   |
| python          | wodby/python                               | 0.1.0   |
| redis           | wodby/redis                                | 0.1.0   |
| ruby            | wodby/ruby                                 | 0.1.0   |
| solr            | wodby/solr                                 | 0.1.0   |
| tailscale       | tailscale/tailscale                        | 0.1.0   |
| valkey          | wodby/valkey                               | 0.1.0   |
| varnish         | wodby/varnish                              | 0.2.0   |
| zookeeper       | wodby/zookeeper                            | 0.1.0   |
