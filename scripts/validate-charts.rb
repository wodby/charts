#!/usr/bin/env ruby

require "open3"
require "yaml"

RELEASE_NAME = "wodby-conformance"
WORKLOAD_NAME = "wodby-conformance-workload"
SERVICE_ACCOUNT_NAME = "wodby-conformance-service-account"
IMAGE_PULL_SECRET_NAME = "wodby-conformance-image-pull-secret"
WORKLOAD_KINDS = %w[Deployment StatefulSet DaemonSet].freeze

CHART_VALUES = {
  "mtproxy" => ["existingSecret=wodby-conformance-existing-secret"],
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
