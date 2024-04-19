# Alloy

Fork of https://github.com/grafana/alloy/tree/main/operations/helm/charts/alloy

- new template: kubernetes-monitoring-telemetry, metrics-service-credentials
- always create overridden default configMap content
- support for namespaces in controller
- values:
  - disabled crds creation  
  - enabled clustering
  - statefulset controller 
  - controller extra volumes and mounts for `kubernetes-monitoring-telemetry`
  - extra ports
  - controller node selector
