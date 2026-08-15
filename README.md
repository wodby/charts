# Helm Charts

These charts are designed to be used for deployment with Wodby [services](https://github.com/wodby/services) and may not be generic enough to be used fully independently.

Some functionality like certificates, certain config maps and network policies are handled directly by Wodby without helm manifests.

## Available charts

The catalog below is generated from each chart's `Chart.yaml` and `values.yaml`. Do not edit it manually; run
`ruby scripts/update-readme.rb` after changing chart metadata.

<!-- BEGIN GENERATED CHART CATALOG -->

| Chart           | Image                                       | Version |
| --------------- | ------------------------------------------- | ------- |
| 3xui            | ghcr.io/mhsanaei/3x-ui                      | 0.1.0   |
| adminer         | wodby/adminer                               | 0.2.0   |
| common          |                                             | 1.0.0   |
| distribution    | registry                                    | 0.1.1   |
| frpc            | wodby/frp                                   | 0.2.1   |
| frps            | wodby/frp                                   | 0.1.0   |
| go              | wodby/go                                    | 0.1.2   |
| gotenberg       | gotenberg/gotenberg                         | 0.1.2   |
| httpd           | wodby/apache                                | 0.2.1   |
| mailpit         | axllent/mailpit                             | 0.2.1   |
| mariadb         | wodby/mariadb                               | 0.2.2   |
| memcached       | wodby/memcached                             | 0.1.0   |
| mtproxy         | telegrammessenger/proxy                     | 0.1.1   |
| nfs-provisioner | registry.k8s.io/sig-storage/nfs-provisioner | 0.3.2   |
| nginx           | wodby/nginx                                 | 0.2.2   |
| node            | wodby/node                                  | 0.2.2   |
| openclaw        | wodby/openclaw                              | 0.1.1   |
| opensmtpd       | wodby/opensmtpd                             | 0.3.1   |
| pgadmin         | dpage/pgadmin4                              | 0.1.0   |
| php-fpm         | wodby/php                                   | 0.2.1   |
| phpmyadmin      | phpmyadmin                                  | 0.1.0   |
| postgres        | wodby/postgres                              | 0.2.1   |
| prometheus      | wodby/prometheus                            | 0.1.0   |
| python          | wodby/python                                | 0.1.2   |
| rabbitmq        | wodby/rabbitmq                              | 0.2.2   |
| redis           | wodby/redis                                 | 0.1.3   |
| ruby            | wodby/ruby                                  | 0.1.2   |
| rustdesk        | rustdesk/rustdesk-server                    | 0.1.0   |
| solr            | wodby/solr                                  | 0.1.2   |
| stateful        | configurable                                | 0.1.0   |
| stateless       | configurable                                | 0.1.1   |
| tailscale       | tailscale/tailscale                         | 0.1.0   |
| valkey          | wodby/valkey                                | 0.1.3   |
| varnish         | wodby/varnish                               | 0.2.1   |
| vinyl           | wodby/vinyl                                 | 0.1.1   |
| zookeeper       | wodby/zookeeper                             | 0.1.0   |

<!-- END GENERATED CHART CATALOG -->

## Release metadata

Each new chart version describes its user-facing changes in the `artifacthub.io/changes` annotation in `Chart.yaml`.
The annotation contains only the changes for that version. Breaking changes that require manual action are documented
in the chart's `UPGRADE.md`.

Repository-specific contribution and validation rules are documented in [`AGENTS.md`](AGENTS.md).
