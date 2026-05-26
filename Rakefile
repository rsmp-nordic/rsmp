require 'bundler/gem_tasks'

task :test do
  sh 'bundle exec sus'
end

CORE_VERSIONS = %w[3.1.2 3.1.3 3.1.4 3.1.5 3.2.0 3.2.1 3.2.2 3.3.0].freeze
TLC_VERSIONS  = %w[1.0.7 1.0.8 1.0.9 1.0.10 1.0.13 1.0.14 1.0.15 1.1.0 1.2.0 1.2.1 1.3.0].freeze

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
      puts "  #{ver}"
      FileUtils.rm_rf(target)
      FileUtils.mkdir_p(target)
      sh "git -C #{tlc_path} archive refs/heads/#{ver} -- schema/ | tar x --strip-components=1 -C #{target}"
    end
  end
end

task default: :test
