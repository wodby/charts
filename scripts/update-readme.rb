#!/usr/bin/env ruby

require "yaml"

BEGIN_MARKER = "<!-- BEGIN GENERATED CHART CATALOG -->"
END_MARKER = "<!-- END GENERATED CHART CATALOG -->"
IMAGE_OVERRIDES = {
  "common" => "",
  "stateful" => "configurable",
  "stateless" => "configurable",
}.freeze

def load_yaml(path)
  YAML.load_file(path) || {}
end

def markdown_cell(value)
  value.to_s.gsub("|", "\\|").gsub(/\s+/, " ").strip
end

def chart_rows
  Dir.glob("*/Chart.yaml").sort.map do |chart_path|
    chart_name = File.dirname(chart_path)
    metadata = load_yaml(chart_path)
    values_path = File.join(chart_name, "values.yaml")
    values = File.exist?(values_path) ? load_yaml(values_path) : {}
    default_registry = values.dig("image", "registry")
    default_image = values.dig("image", "repository")
    if default_registry && default_registry != "docker.io" && default_image
      default_image = "#{default_registry}/#{default_image}"
    end
    image = IMAGE_OVERRIDES.fetch(chart_name, default_image)

    raise "#{chart_path} has no name" if metadata["name"].to_s.empty?
    raise "#{chart_path} has no version" if metadata["version"].to_s.empty?
    raise "#{chart_name} has no catalog image" if image.nil?

    [metadata["name"], image, metadata["version"]].map { |cell| markdown_cell(cell) }
  end
end

def markdown_table(rows)
  all_rows = [["Chart", "Image", "Version"], *rows]
  widths = all_rows.transpose.map { |column| column.map(&:length).max }
  render = lambda do |row|
    "| #{row.each_with_index.map { |cell, index| cell.ljust(widths[index]) }.join(" | ")} |"
  end
  separator = "| #{widths.map { |width| "-" * width }.join(" | ")} |"

  [render.call(all_rows.first), separator, *rows.map { |row| render.call(row) }].join("\n")
end

def replace_catalog(readme, table)
  unless readme.include?(BEGIN_MARKER) && readme.include?(END_MARKER)
    raise "README.md must contain #{BEGIN_MARKER} and #{END_MARKER}"
  end

  before, after_begin = readme.split(BEGIN_MARKER, 2)
  _generated, after = after_begin.split(END_MARKER, 2)
  raise "README.md contains an invalid generated catalog section" if after.nil?

  "#{before}#{BEGIN_MARKER}\n\n#{table}\n\n#{END_MARKER}#{after}"
end

root = File.expand_path("..", __dir__)
Dir.chdir(root)

readme_path = "README.md"
current = File.read(readme_path)
expected = replace_catalog(current, markdown_table(chart_rows))

if ARGV == ["--check"]
  if current != expected
    warn "README.md chart catalog is out of date; run ruby scripts/update-readme.rb"
    exit 1
  end
elsif ARGV.empty?
  File.write(readme_path, expected)
  puts "Updated README.md chart catalog"
else
  warn "usage: ruby scripts/update-readme.rb [--check]"
  exit 2
end
