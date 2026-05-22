require 'bundler/gem_tasks'
require 'rsmp/convert/import/yaml'
require 'rsmp/convert/export/json_schema'

task :test do
  sh 'bundle exec sus'
end

# Regenerate all SXL JSON Schemas.
# Warning: This will destructively override all relevant files. Any changes will be lost!
task :regenerate do
  puts 'Regenerating SXL JSON Schemas:'
  Dir.glob('schemas/tlc/*/sxl.yaml').each do |path|
    puts "  #{File.dirname(path)}"
    sxl = RSMP::Convert::Import::YAML.read path
    RSMP::Convert::Export::JSONSchema.write sxl, File.dirname(path)
  end
end

CORE_VERSIONS = %w[3.1.2 3.1.3 3.1.4 3.1.5 3.2.0 3.2.1 3.2.2].freeze
TLC_VERSIONS  = %w[1.0.7 1.0.8 1.0.9 1.0.10 1.0.13 1.0.14 1.0.15 1.1.0 1.2.0 1.2.1].freeze

# Update vendored schemas from source repos.
# Usage: rake schemas:update[/path/to/rsmp_core,/path/to/rsmp_sxl_traffic_lights]
# Defaults to sibling directories ../rsmp_core and ../rsmp_sxl_traffic_lights.
namespace :schemas do
  task :update, [:core_path, :tlc_path] do |_t, args|
    core_path = File.expand_path(args[:core_path] || '../rsmp_core')
    tlc_path  = File.expand_path(args[:tlc_path]  || '../rsmp_sxl_traffic_lights')

    puts "Updating core schemas from #{core_path}:"
    CORE_VERSIONS.each do |ver|
      target = "schemas/core/#{ver}"
      puts "  #{ver}"
      FileUtils.rm_rf(target)
      FileUtils.mkdir_p(target)
      sh "git -C #{core_path} archive refs/heads/#{ver} -- schema/ | tar x --strip-components=1 -C #{target}"
    end

    puts "Updating TLC schemas from #{tlc_path}:"
    TLC_VERSIONS.each do |ver|
      target = "schemas/tlc/#{ver}"
      puts "  #{ver}"
      FileUtils.rm_rf(target)
      FileUtils.mkdir_p(target)
      sh "git -C #{tlc_path} archive refs/heads/#{ver} -- schema/ | tar x --strip-components=1 -C #{target}"
    end
  end
end

task default: :test
