#!/usr/bin/env ruby

require "open3"
require "yaml"

RELEASE_NAME = "wodby-conformance"
WORKLOAD_NAME = "wodby-conformance-workload"
SERVICE_ACCOUNT_NAME = "wodby-conformance-service-account"
IMAGE_PULL_SECRET_NAME = "wodby-conformance-image-pull-secret"
APP_NAME = "wodby-conformance-app"
WORKLOAD_KINDS = %w[Deployment StatefulSet DaemonSet].freeze

CHART_VALUES = {
  "frps" => ["existingSecret=wodby-conformance-existing-secret"],
  "mtproxy" => ["existingSecret=wodby-conformance-existing-secret"],
}.freeze

DEPLOYMENT_RECREATE_DEFAULTS = %w[
  adminer
  distribution
  frpc
  frps
  memcached
  pgadmin
  phpmyadmin
].freeze

LEGACY_DEPLOYMENT_STRATEGY_CHARTS = %w[
  frps
  httpd
  mtproxy
  nginx
  varnish
  vinyl
].freeze

SHUTDOWN_GRACE_DEFAULTS = {
  "distribution" => 60,
  "gotenberg" => 60,
  "nfs-provisioner" => 100,
  "rabbitmq" => 270,
  "solr" => 60,
}.freeze

GRACEFUL_SHUTDOWN_CHARTS = %w[
  adminer
  distribution
  gotenberg
  httpd
  nginx
  pgadmin
  php-fpm
  phpmyadmin
  prometheus
  rabbitmq
  solr
  varnish
  vinyl
].freeze

LEGACY_LIFECYCLE_CHARTS = %w[
  adminer
  pgadmin
  phpmyadmin
  rabbitmq
].freeze

NESTED_DEPLOYMENT_VALUE_PATHS = {
  "mariadb" => {
    strategy: "primary.updateStrategy",
    min_ready: "primary.minReadySeconds",
    shutdown_grace: "primary.terminationGracePeriodSeconds",
  },
  "postgres" => {
    strategy: "primary.updateStrategy",
    min_ready: "primary.minReadySeconds",
    shutdown_grace: "primary.terminationGracePeriodSeconds",
  },
}.freeze

SECONDARY_WORKLOADS = {
  "mariadb" => {
    component: "secondary",
    overrides: [
      "architecture=replication",
      "secondary.replicaCount=1",
      "secondary.updateStrategy.type=OnDelete",
      "secondary.minReadySeconds=0",
      "secondary.terminationGracePeriodSeconds=0",
    ],
  },
  "postgres" => {
    component: "read",
    overrides: [
      "architecture=replication",
      "readReplicas.replicaCount=1",
      "readReplicas.updateStrategy.type=OnDelete",
      "readReplicas.minReadySeconds=0",
      "readReplicas.terminationGracePeriodSeconds=0",
    ],
  },
}.freeze

def run!(*args)
  stdout, stderr, status = Open3.capture3(*args)
  return stdout if status.success?

  warn stdout unless stdout.empty?
  warn stderr unless stderr.empty?
  raise "command failed: #{args.join(" ")}"
end

def render(chart, overrides = [])
  args = [
    "helm", "template", RELEASE_NAME, chart,
    "--namespace", "default",
  ]
  (CHART_VALUES.fetch(chart, []) + overrides).each do |override|
    args.concat(["--set", override])
  end
  YAML.load_stream(run!(*args)).compact.select { |doc| doc.is_a?(Hash) }
end

def workloads(documents)
  documents.select { |doc| WORKLOAD_KINDS.include?(doc["kind"]) }
end

def target_workload(documents)
  matches = workloads(documents).select { |doc| doc.dig("metadata", "name") == WORKLOAD_NAME }
  raise "expected exactly one workload named #{WORKLOAD_NAME}, got #{matches.length}" unless matches.length == 1

  matches.first
end

def assert_no_hpa!(chart, documents)
  return unless documents.any? { |doc| doc["kind"] == "HorizontalPodAutoscaler" }

  raise "#{chart} renders a HorizontalPodAutoscaler; Wodby backend owns autoscaling"
end

def assert_workload_has_containers!(chart, workload)
  containers = Array(workload.dig("spec", "template", "spec", "containers"))
  return unless containers.empty?

  raise "#{chart} renders a workload without containers"
end

def assert_app_name_override!(chart, documents)
  labels = documents.map { |document| document.dig("metadata", "labels", "app.kubernetes.io/name") }.compact
  if labels.empty?
    raise "#{chart} does not render app.kubernetes.io/name on any resource"
  end
  unless labels.all? { |label| label == APP_NAME }
    raise "#{chart} does not apply nameOverride consistently to resource labels: #{labels.uniq.inspect}"
  end

  workloads(documents).each do |workload|
    selector = workload.dig("spec", "selector", "matchLabels", "app.kubernetes.io/name")
    pod_label = workload.dig("spec", "template", "metadata", "labels", "app.kubernetes.io/name")
    unless selector == APP_NAME && pod_label == APP_NAME
      raise "#{chart} does not apply nameOverride consistently to #{workload["kind"]} selectors and pod labels"
    end
  end
end

def assert_distribution_auth_modes!
  {
    "disabled" => false,
    "enabled" => true,
  }.each do |mode, enabled|
    documents = render("distribution", [
      "fullnameOverride=#{WORKLOAD_NAME}",
      "auth.htpasswd.enabled=#{enabled}",
      "existingEnvSecret=wodby-conformance-existing-secret",
    ])
    pod_spec = target_workload(documents).dig("spec", "template", "spec")
    container_names = Array(pod_spec["containers"]).map { |container| container["name"] }
    unless container_names == ["distribution"]
      raise "distribution renders containers=#{container_names.inspect} with htpasswd #{mode}"
    end

    init_container_names = Array(pod_spec["initContainers"]).map { |container| container["name"] }
    has_htpasswd = init_container_names.include?("htpasswd")
    unless has_htpasswd == enabled
      raise "distribution htpasswd init container presence does not match htpasswd #{mode}"
    end
  end
end

def assert_pgadmin_linked_database_login!
  secret_name = "wodby-conformance-database"
  secret_key = "PGADMIN_DB_PASSWORD"
  documents = render("pgadmin", [
    "fullnameOverride=#{WORKLOAD_NAME}",
    "server.enabled=true",
    "server.host=postgres",
    "server.port=5432",
    "server.username=app",
    "server.maintenanceDatabase=app",
    "server.passwordSecret=#{secret_name}",
    "server.passwordKey=#{secret_key}",
  ])
  pod_spec = target_workload(documents).dig("spec", "template", "spec")
  init_container = Array(pod_spec["initContainers"]).find { |container| container["name"] == "pgpass" }
  raise "pgadmin does not render the pgpass init container" if init_container.nil?

  password_env = Array(init_container["env"]).find { |env| env["name"] == "PGPASS_PASSWORD" }
  unless password_env&.dig("valueFrom", "secretKeyRef") == {"name" => secret_name, "key" => secret_key}
    raise "pgadmin pgpass init container does not read the configured password Secret"
  end

  main_container = Array(pod_spec["containers"]).find { |container| container["name"] == "pgadmin" }
  unless main_container["command"] == ["/venv/bin/python3"] &&
         main_container["args"] == ["/opt/wodby/server-import-entrypoint.py"]
    raise "pgadmin does not resolve a persisted administrator before linked server import"
  end

  resolver_mount = Array(main_container["volumeMounts"]).find do |mount|
    mount["name"] == "server-import-entrypoint"
  end
  unless resolver_mount == {
    "name" => "server-import-entrypoint",
    "mountPath" => "/opt/wodby/server-import-entrypoint.py",
    "subPath" => "server-import-entrypoint.py",
    "readOnly" => true,
  }
    raise "pgadmin does not mount the persisted administrator resolver read-only"
  end

  resolver = documents.find do |document|
    document["kind"] == "ConfigMap" &&
      document.dig("metadata", "name") == "#{WORKLOAD_NAME}-server-import-entrypoint"
  end
  resolver_script = resolver&.dig("data", "server-import-entrypoint.py")
  unless resolver_script&.include?("resolve_server_import_email") &&
         resolver_script&.include?("refresh_pgpass")
    raise "pgadmin does not render the persisted administrator and password-file preparation"
  end

  replace_servers_env = Array(main_container["env"]).find do |env|
    env["name"] == "PGADMIN_REPLACE_SERVERS_ON_STARTUP"
  end
  unless replace_servers_env == {"name" => "PGADMIN_REPLACE_SERVERS_ON_STARTUP", "value" => "True"}
    raise "pgadmin does not enable replacing server definitions with the case-sensitive value expected by the image"
  end

  pgpass_env = Array(main_container["env"]).find { |env| env["name"] == "PGPASS_FILE" }
  unless pgpass_env == {"name" => "PGPASS_FILE", "value" => "/pgpass/pgpass"}
    raise "pgadmin does not configure PGPASS_FILE for linked database login"
  end

  pgpass_mount = Array(main_container["volumeMounts"]).find { |mount| mount["name"] == "pgpass" }
  unless pgpass_mount == {"name" => "pgpass", "mountPath" => "/pgpass", "readOnly" => true}
    raise "pgadmin does not mount the generated password file read-only"
  end

  pgpass_volume = Array(pod_spec["volumes"]).find { |volume| volume["name"] == "pgpass" }
  unless pgpass_volume == {"name" => "pgpass", "emptyDir" => {}}
    raise "pgadmin does not provide storage for the generated password file"
  end

  custom_container = target_workload(render("pgadmin", [
    "fullnameOverride=#{WORKLOAD_NAME}",
    "server.enabled=true",
    "command[0]=/bin/echo",
    "args[0]=custom",
  ])).dig("spec", "template", "spec", "containers").first
  unless custom_container["command"] == ["/bin/echo"] && custom_container["args"] == ["custom"]
    raise "pgadmin persisted administrator resolution overrides a custom command"
  end
end

def main_container(chart, overrides = [])
  Array(
    target_workload(render(chart, ["fullnameOverride=#{WORKLOAD_NAME}", *overrides]))
      .dig("spec", "template", "spec", "containers")
  ).first
end

def pre_stop_command(chart, overrides = [])
  main_container(chart, overrides)&.dig("lifecycle", "preStop", "exec", "command")
end

def assert_graceful_shutdown_contract!(chart, values)
  return unless GRACEFUL_SHUTDOWN_CHARTS.include?(chart)

  default_command = pre_stop_command(chart)
  if default_command.nil? || default_command.empty?
    raise "#{chart} does not render its default graceful shutdown hook"
  end

  custom_command = ["custom-lifecycle-hook"]
  actual_custom = pre_stop_command(chart, [
    "lifecycleHooks.preStop.exec.command[0]=#{custom_command.first}",
  ])
  unless actual_custom == custom_command
    raise "#{chart} does not let custom lifecycle hooks override the default: #{actual_custom.inspect}"
  end

  unless pre_stop_command(chart, ["gracefulShutdown.enabled=false"]).nil?
    raise "#{chart} does not remove its default lifecycle hook when graceful shutdown is disabled"
  end

  if values.key?("command")
    lifecycle = main_container(chart, ["command[0]=custom-command"])["lifecycle"]
    unless lifecycle.nil?
      raise "#{chart} applies a process-specific lifecycle hook to a custom command"
    end
  end

  if LEGACY_LIFECYCLE_CHARTS.include?(chart)
    legacy_command = ["legacy-lifecycle-hook"]
    actual_legacy = pre_stop_command(chart, [
      "lifecycle.preStop.exec.command[0]=#{legacy_command.first}",
    ])
    unless actual_legacy == legacy_command
      raise "#{chart} no longer supports its legacy lifecycle value: #{actual_legacy.inspect}"
    end
  end

  if chart == "nginx"
    unless default_command.last.include?("sudo nginx -s quit")
      raise "nginx graceful shutdown hook does not request a graceful NGINX quit"
    end
  elsif chart == "rabbitmq"
    unless default_command.last.include?("rabbitmq-upgrade drain")
      raise "rabbitmq graceful shutdown hook does not drain the node"
    end
    clustered_command = pre_stop_command(chart, ["replicaCount=2"])
    unless clustered_command.last.include?("await_online_quorum_plus_one")
      raise "rabbitmq clustered shutdown does not wait for safe quorum state"
    end
  else
    unless default_command.last == "sleep 5"
      raise "#{chart} graceful shutdown hook does not render the default endpoint-drain delay"
    end
    delayed_command = pre_stop_command(chart, ["gracefulShutdown.preStopDelaySeconds=17"])
    unless delayed_command.last == "sleep 17"
      raise "#{chart} does not apply the configured endpoint-drain delay"
    end
  end
end

def assert_distribution_drain_timeout!
  default_env = Array(main_container("distribution")["env"])
  default_timeout = default_env.find { |env| env["name"] == "REGISTRY_HTTP_DRAINTIMEOUT" }
  unless default_timeout == {"name" => "REGISTRY_HTTP_DRAINTIMEOUT", "value" => "45s"}
    raise "distribution does not configure the default HTTP drain timeout"
  end

  custom_env = Array(main_container("distribution", [
    "envVars[0].name=REGISTRY_HTTP_DRAINTIMEOUT",
    "envVars[0].value=20s",
  ])["env"])
  drain_timeouts = custom_env.select { |env| env["name"] == "REGISTRY_HTTP_DRAINTIMEOUT" }
  unless drain_timeouts == [{"name" => "REGISTRY_HTTP_DRAINTIMEOUT", "value" => "20s"}]
    raise "distribution does not preserve a custom HTTP drain timeout without duplicates"
  end
end

def value_path_candidates(value, prefix = nil, candidates = [])
  return candidates unless value.is_a?(Hash)

  value.each do |key, nested|
    path = [prefix, key].compact.join(".")
    candidates << path if %w[replicas replicaCount].include?(key)
    value_path_candidates(nested, path, candidates)
  end
  candidates
end

def replica_path(chart, values)
  default_overrides = [
    "fullnameOverride=#{WORKLOAD_NAME}",
    "replicas=0",
    "replicaCount=0",
  ]
  workload = target_workload(render(chart, default_overrides))
  return %w[replicas=0 replicaCount=0] if workload.dig("spec", "replicas") == 0

  value_path_candidates(values).uniq.each do |path|
    next if %w[replicas replicaCount].include?(path)

    workload = target_workload(render(chart, [
      "fullnameOverride=#{WORKLOAD_NAME}",
      "#{path}=0",
    ]))
    return ["#{path}=0"] if workload.dig("spec", "replicas") == 0
  end

  raise "#{chart} has no Helm replica value that scales its primary workload to zero"
end

def with_replica_value(overrides, replicas)
  overrides.map { |override| override.sub(/=0\z/, "=#{replicas}") }
end

def deployment_value_paths(chart, kind)
  return NESTED_DEPLOYMENT_VALUE_PATHS.fetch(chart) if NESTED_DEPLOYMENT_VALUE_PATHS.key?(chart)

  {
    strategy: kind == "Deployment" ? "strategy" : "updateStrategy",
    min_ready: "minReadySeconds",
    progress_deadline: "progressDeadlineSeconds",
    shutdown_grace: "terminationGracePeriodSeconds",
  }
end

def assert_deployment_defaults!(chart, workload)
  spec = workload.fetch("spec")
  kind = workload.fetch("kind")
  expected_strategy = DEPLOYMENT_RECREATE_DEFAULTS.include?(chart) ? "Recreate" : "RollingUpdate"
  strategy_key = kind == "Deployment" ? "strategy" : "updateStrategy"
  strategy = spec.fetch(strategy_key)

  unless strategy["type"] == expected_strategy
    raise "#{chart} renders #{strategy_key}.type=#{strategy["type"].inspect}, expected #{expected_strategy}"
  end
  unless spec["minReadySeconds"] == 10
    raise "#{chart} renders minReadySeconds=#{spec["minReadySeconds"].inspect}, expected 10"
  end
  if kind == "Deployment"
    unless spec["progressDeadlineSeconds"] == 900
      raise "#{chart} renders progressDeadlineSeconds=#{spec["progressDeadlineSeconds"].inspect}, expected 900"
    end
    if expected_strategy == "RollingUpdate"
      rolling = strategy.fetch("rollingUpdate")
      unless rolling["maxUnavailable"] == 0 && rolling["maxSurge"] == 1
        raise "#{chart} does not render the availability-preserving RollingUpdate defaults"
      end
    end
  elsif spec.key?("progressDeadlineSeconds")
    raise "#{chart} renders progressDeadlineSeconds for #{kind}"
  end

  expected_grace = SHUTDOWN_GRACE_DEFAULTS.fetch(chart, 30)
  actual_grace = spec.dig("template", "spec", "terminationGracePeriodSeconds")
  unless actual_grace == expected_grace
    raise "#{chart} renders terminationGracePeriodSeconds=#{actual_grace.inspect}, expected #{expected_grace}"
  end
end

def assert_deployment_overrides!(chart, workload)
  kind = workload.fetch("kind")
  paths = deployment_value_paths(chart, kind)
  overrides = [
    "fullnameOverride=#{WORKLOAD_NAME}",
    "#{paths.fetch(:min_ready)}=0",
    "#{paths.fetch(:shutdown_grace)}=0",
  ]
  if kind == "Deployment"
    overrides.concat([
      "#{paths.fetch(:strategy)}.type=RollingUpdate",
      "#{paths.fetch(:strategy)}.rollingUpdate.maxUnavailable=1",
      "#{paths.fetch(:strategy)}.rollingUpdate.maxSurge=2",
      "#{paths.fetch(:progress_deadline)}=1",
    ])
  else
    overrides << "#{paths.fetch(:strategy)}.type=OnDelete"
  end

  overridden = target_workload(render(chart, overrides)).fetch("spec")
  strategy_key = kind == "Deployment" ? "strategy" : "updateStrategy"
  expected_strategy = kind == "Deployment" ? "RollingUpdate" : "OnDelete"
  unless overridden.dig(strategy_key, "type") == expected_strategy
    raise "#{chart} does not apply the configured #{strategy_key}.type"
  end
  unless overridden["minReadySeconds"] == 0
    raise "#{chart} does not render minReadySeconds=0"
  end
  unless overridden.dig("template", "spec", "terminationGracePeriodSeconds") == 0
    raise "#{chart} does not render terminationGracePeriodSeconds=0"
  end

  non_rolling_type = kind == "Deployment" ? "Recreate" : "OnDelete"
  non_rolling = target_workload(render(chart, [
    "fullnameOverride=#{WORKLOAD_NAME}",
    "#{paths.fetch(:strategy)}.type=#{non_rolling_type}",
  ])).fetch("spec")
  non_rolling_strategy = non_rolling.fetch(strategy_key)
  unless non_rolling_strategy["type"] == non_rolling_type
    raise "#{chart} does not apply the #{non_rolling_type} #{strategy_key}"
  end
  if non_rolling_strategy.key?("rollingUpdate")
    raise "#{chart} renders rollingUpdate settings with the #{non_rolling_type} #{strategy_key}"
  end

  return unless kind == "Deployment"

  rolling = overridden.fetch("strategy").fetch("rollingUpdate")
  unless rolling["maxUnavailable"] == 1 && rolling["maxSurge"] == 2
    raise "#{chart} does not apply configured RollingUpdate capacity"
  end
  unless overridden["progressDeadlineSeconds"] == 1
    raise "#{chart} does not render progressDeadlineSeconds=1"
  end

  return unless LEGACY_DEPLOYMENT_STRATEGY_CHARTS.include?(chart)

  legacy = target_workload(render(chart, [
    "fullnameOverride=#{WORKLOAD_NAME}",
    "updateStrategy.type=Recreate",
  ])).fetch("spec")
  unless legacy.dig("strategy", "type") == "Recreate"
    raise "#{chart} does not preserve the deprecated updateStrategy override"
  end
  if legacy.fetch("strategy").key?("rollingUpdate")
    raise "#{chart} renders rollingUpdate settings with the deprecated Recreate updateStrategy override"
  end
end

def assert_secondary_workload_overrides!(chart)
  return unless SECONDARY_WORKLOADS.key?(chart)

  settings = SECONDARY_WORKLOADS.fetch(chart)
  matches = workloads(render(chart, settings.fetch(:overrides))).select do |workload|
    workload.dig("metadata", "labels", "app.kubernetes.io/component") == settings.fetch(:component)
  end
  unless matches.length == 1
    raise "#{chart} expected one #{settings.fetch(:component)} workload, got #{matches.length}"
  end

  spec = matches.first.fetch("spec")
  unless spec.dig("updateStrategy", "type") == "OnDelete"
    raise "#{chart} secondary workload does not apply its configured update strategy"
  end
  if spec.fetch("updateStrategy").key?("rollingUpdate")
    raise "#{chart} secondary workload renders rollingUpdate settings with OnDelete"
  end
  unless spec["minReadySeconds"] == 0
    raise "#{chart} secondary workload does not render minReadySeconds=0"
  end
  unless spec.dig("template", "spec", "terminationGracePeriodSeconds") == 0
    raise "#{chart} secondary workload does not render terminationGracePeriodSeconds=0"
  end
end

root = File.expand_path("..", __dir__)
Dir.chdir(root)

charts = Dir.glob("*/Chart.yaml").map { |path| File.dirname(path) }.sort
raise "no charts found" if charts.empty?

charts.each do |chart|
  chart_metadata = YAML.load_file(File.join(chart, "Chart.yaml")) || {}
  values_path = File.join(chart, "values.yaml")
  values = File.exist?(values_path) ? (YAML.load_file(values_path) || {}) : {}
  if values.key?("autoscaling")
    raise "#{chart} declares chart-owned autoscaling values; Wodby backend owns autoscaling"
  end

  hpa_templates = Dir.glob(File.join(chart, "templates", "**", "*"), File::FNM_DOTMATCH).select do |path|
    File.file?(path) && File.read(path).include?("HorizontalPodAutoscaler")
  end
  unless hpa_templates.empty?
    raise "#{chart} contains chart-owned HorizontalPodAutoscaler templates: #{hpa_templates.join(", ")}"
  end

  lint_args = ["helm", "lint", "--strict", chart]
  CHART_VALUES.fetch(chart, []).each { |override| lint_args.concat(["--set", override]) }

  run!("helm", "dependency", "build", "--skip-refresh", chart) unless ENV["SKIP_DEPENDENCY_BUILD"] == "1"
  run!(*lint_args)

  if chart_metadata["type"] == "library"
    puts "#{chart}: linted library chart"
    next
  end

  unless values.key?("nameOverride") && values.key?("fullnameOverride")
    raise "#{chart} must declare nameOverride and fullnameOverride in values.yaml"
  end

  default_documents = render(chart)
  raise "#{chart} does not render a workload" if workloads(default_documents).empty?
  assert_no_hpa!(chart, default_documents)

  named_documents = render(chart, ["fullnameOverride=#{WORKLOAD_NAME}"])
  target_workload(named_documents)

  primary = target_workload(named_documents)
  app_named_documents = render(chart, [
    "fullnameOverride=#{WORKLOAD_NAME}",
    "nameOverride=#{APP_NAME}",
  ])
  assert_app_name_override!(chart, app_named_documents)
  assert_workload_has_containers!(chart, primary)
  assert_distribution_auth_modes! if chart == "distribution"
  assert_pgadmin_linked_database_login! if chart == "pgadmin"
  assert_graceful_shutdown_contract!(chart, values)
  assert_distribution_drain_timeout! if chart == "distribution"
  assert_deployment_defaults!(chart, primary)
  assert_deployment_overrides!(chart, primary)
  assert_secondary_workload_overrides!(chart)
  unless primary["kind"] == "DaemonSet"
    zero_overrides = replica_path(chart, values)
    [0, 1].each do |replicas|
      documents = render(chart, [
        "fullnameOverride=#{WORKLOAD_NAME}",
        *with_replica_value(zero_overrides, replicas),
      ])
      actual = target_workload(documents).dig("spec", "replicas")
      raise "#{chart} renders replicas=#{actual.inspect}, expected #{replicas}" unless actual == replicas
    end
  end

  if values["serviceAccount"].is_a?(Hash) && values["serviceAccount"].key?("name")
    service_account_overrides = [
      "fullnameOverride=#{WORKLOAD_NAME}",
      "serviceAccount.name=#{SERVICE_ACCOUNT_NAME}",
    ]
    if values["serviceAccount"].key?("create")
      service_account_overrides << "serviceAccount.create=false"
    end
    documents = render(chart, service_account_overrides)
    actual = target_workload(documents).dig("spec", "template", "spec", "serviceAccountName")
    unless actual == SERVICE_ACCOUNT_NAME
      raise "#{chart} does not apply serviceAccount.name to the workload pod"
    end
    if documents.any? do |document|
         document["kind"] == "ServiceAccount" &&
           document.dig("metadata", "name") == SERVICE_ACCOUNT_NAME
       end
      raise "#{chart} still creates #{SERVICE_ACCOUNT_NAME} when serviceAccount.create is false"
    end
  end

  if values["image"].is_a?(Hash) && values["image"].key?("pullSecrets")
    documents = render(chart, [
      "fullnameOverride=#{WORKLOAD_NAME}",
      "image.pullSecrets[0]=#{IMAGE_PULL_SECRET_NAME}",
    ])
    secrets = Array(target_workload(documents).dig("spec", "template", "spec", "imagePullSecrets"))
      .map { |secret| secret.is_a?(Hash) ? secret["name"] : secret }
    unless secrets.include?(IMAGE_PULL_SECRET_NAME)
      raise "#{chart} declares image.pullSecrets but does not apply it to the workload pod"
    end
  end

  puts "#{chart}: conformance passed"
end

puts "Validated #{charts.length} charts"
