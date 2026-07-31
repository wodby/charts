#!/usr/bin/env ruby

require "open3"
require "rubygems"
require "yaml"

CHANGE_ANNOTATION = "artifacthub.io/changes"
CHANGE_KINDS = %w[added changed deprecated removed fixed security].freeze
RUNTIME_FILES = %w[.helmignore Chart.lock Chart.yaml values.schema.json values.yaml].freeze
RUNTIME_DIRECTORIES = %w[charts crds files templates].freeze

def run(*args)
  stdout, stderr, status = Open3.capture3(*args)
  [stdout, stderr, status.success?]
end

def chart_metadata(path)
  YAML.load_file(path) || {}
end

def previous_chart_metadata(base_ref, path)
  stdout, _stderr, success = run("git", "show", "#{base_ref}:#{path}")
  return nil unless success

  YAML.safe_load(stdout, aliases: false) || {}
end

def change_entries(metadata, chart, errors)
  raw = metadata.dig("annotations", CHANGE_ANNOTATION)
  return nil if raw.nil?
  unless raw.is_a?(String)
    errors << "#{chart}: #{CHANGE_ANNOTATION} must be a YAML string"
    return nil
  end
  return nil if raw.strip.empty?

  entries = YAML.safe_load(raw, aliases: false)
  unless entries.is_a?(Array) && !entries.empty?
    errors << "#{chart}: #{CHANGE_ANNOTATION} must contain a non-empty YAML list"
    return nil
  end

  entries.each_with_index do |entry, index|
    unless entry.is_a?(Hash)
      errors << "#{chart}: change entry #{index + 1} must contain kind and description"
      next
    end

    kind = entry["kind"]
    description = entry["description"]
    unless CHANGE_KINDS.include?(kind)
      errors << "#{chart}: change entry #{index + 1} kind must be one of #{CHANGE_KINDS.join(", ")}"
    end
    unless description.is_a?(String) && !description.strip.empty?
      errors << "#{chart}: change entry #{index + 1} must have a non-empty description"
    end
  end

  entries
rescue Psych::SyntaxError => e
  errors << "#{chart}: #{CHANGE_ANNOTATION} is invalid YAML: #{e.problem}"
  nil
end

def runtime_effective_path?(relative_path)
  return true if RUNTIME_FILES.include?(relative_path)

  RUNTIME_DIRECTORIES.any? { |directory| relative_path.start_with?("#{directory}/") }
end

root = File.expand_path("..", __dir__)
Dir.chdir(root)

errors = []
chart_paths = Dir.glob("*/Chart.yaml").sort
metadata_by_chart = chart_paths.to_h do |path|
  chart = File.dirname(path)
  metadata = chart_metadata(path)
  change_entries(metadata, chart, errors)
  [chart, metadata]
end

base_ref = ENV.fetch("CHARTS_BASE_REF", "").strip
base_ref = "" if base_ref.match?(/\A0+\z/)

unless base_ref.empty?
  _stdout, stderr, success = run("git", "cat-file", "-e", "#{base_ref}^{commit}")
  raise "cannot resolve CHARTS_BASE_REF #{base_ref}: #{stderr.strip}" unless success

  stdout, stderr, success = run("git", "diff", "--name-only", base_ref, "HEAD", "--")
  raise "cannot compare chart changes with #{base_ref}: #{stderr.strip}" unless success
  changed_paths = stdout.lines(chomp: true)

  metadata_by_chart.each do |chart, metadata|
    path = File.join(chart, "Chart.yaml")
    previous = previous_chart_metadata(base_ref, path)
    chart_changes = changed_paths.each_with_object([]) do |changed_path, matches|
      prefix = "#{chart}/"
      next unless changed_path.start_with?(prefix)

      matches << changed_path.delete_prefix(prefix)
    end
    runtime_changes = chart_changes.select { |changed_path| runtime_effective_path?(changed_path) }
    previous_version = previous&.fetch("version", nil)
    current_version = metadata["version"]
    version_changed = previous.nil? || previous_version != current_version

    if !runtime_changes.empty? && !version_changed
      errors << "#{chart}: runtime-effective files changed without a chart version bump: #{runtime_changes.join(", ")}"
    end

    next unless version_changed

    current_changes = metadata.dig("annotations", CHANGE_ANNOTATION)
    previous_changes = previous&.dig("annotations", CHANGE_ANNOTATION)
    if current_changes.nil? || !current_changes.is_a?(String) || current_changes.strip.empty?
      errors << "#{chart}: version changed from #{previous_version || "new chart"} to #{current_version}, but #{CHANGE_ANNOTATION} is empty"
    elsif !previous.nil? && current_changes == previous_changes
      errors << "#{chart}: version changed from #{previous_version} to #{current_version}, but #{CHANGE_ANNOTATION} was not replaced"
    end

    next if previous.nil?

    begin
      current_semver = Gem::Version.new(current_version.to_s.split("+", 2).first)
      previous_semver = Gem::Version.new(previous_version.to_s.split("+", 2).first)
      unless current_semver > previous_semver
        errors << "#{chart}: chart version must increase, got #{previous_version} to #{current_version}"
      end
    rescue ArgumentError => e
      errors << "#{chart}: cannot compare chart versions #{previous_version} and #{current_version}: #{e.message}"
    end
  end
end

unless errors.empty?
  warn errors.map { |error| "- #{error}" }.join("\n")
  exit 1
end

if base_ref.empty?
  puts "Validated release metadata for #{chart_paths.length} charts (change comparison skipped without CHARTS_BASE_REF)"
else
  puts "Validated release metadata for #{chart_paths.length} charts against #{base_ref}"
end
