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

task default: :test
