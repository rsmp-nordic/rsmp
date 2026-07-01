require 'bundler/gem_tasks'
require 'fileutils'
require 'open3'
require 'yaml'

require_relative 'lib/rsmp/convert/import/yaml'
require_relative 'lib/rsmp/convert/export/json_schema'

task :test do
  sh 'bundle exec sus'
end

CORE_VERSIONS = %w[3.1.2 3.1.3 3.1.4 3.1.5 3.2.0 3.2.1 3.2.2 3.3.0].freeze
TLC_VERSIONS  = %w[1.0.7 1.0.8 1.0.9 1.0.10 1.0.13 1.0.14 1.0.15 1.1.0 1.2.0 1.2.1 1.3.0].freeze

def git_show!(repo_path, ref)
  output, status = Open3.capture2e('git', '-C', repo_path, 'show', ref)
  raise "Could not read #{ref} from #{repo_path}:\n#{output}" unless status.success?

  output
end

def require_minimum_core_version!(source_path)
  yaml = YAML.load_file(source_path)
  minimum_core_version = yaml.dig('meta', 'minimum_core_version')
  raise "Missing meta.minimum_core_version in #{source_path}" if minimum_core_version.nil? || minimum_core_version.to_s.empty?
end

# Update vendored schemas from source repos.
# Usage: rake schemas:update[/path/to/rsmp_core,/path/to/rsmp_sxl_traffic_lights]
# Defaults to sibling directories ../rsmp_core and ../rsmp_sxl_traffic_lights.
#
# NOTE: The source repos must have the version branches up to date locally.
# If the remote has been updated, fetch first:
#   git -C ../rsmp_core fetch
#   git -C ../rsmp_sxl_traffic_lights fetch
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
      source = File.join(target, 'source', 'sxl.yaml')
      puts "  #{ver}"
      FileUtils.rm_rf(target)
      FileUtils.mkdir_p(File.dirname(source))
      File.write(source, git_show!(tlc_path, "refs/heads/#{ver}:schema/sxl.yaml"))
      require_minimum_core_version!(source)
      sxl = RSMP::Convert::Import::YAML.read(source)
      RSMP::Convert::Export::JSONSchema.write(sxl, target)
    end
  end
end

task default: :test
