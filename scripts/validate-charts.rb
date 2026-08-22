#!/usr/bin/env ruby

require "open3"
require "yaml"

RELEASE_NAME = "wodby-conformance"
WORKLOAD_NAME = "wodby-conformance-workload"
SERVICE_ACCOUNT_NAME = "wodby-conformance-service-account"
IMAGE_PULL_SECRET_NAME = "wodby-conformance-image-pull-secret"
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
  "nfs-provisioner" => 100,
  "rabbitmq" => 120,
}.freeze

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

  default_documents = render(chart)
  raise "#{chart} does not render a workload" if workloads(default_documents).empty?
  assert_no_hpa!(chart, default_documents)

  named_documents = render(chart, ["fullnameOverride=#{WORKLOAD_NAME}"])
  target_workload(named_documents)

  primary = target_workload(named_documents)
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
