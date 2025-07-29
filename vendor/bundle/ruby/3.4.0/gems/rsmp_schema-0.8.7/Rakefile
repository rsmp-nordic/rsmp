# frozen_string_literal: true
require "bundler/gem_tasks"
require "bundler/setup"
require "rsmp_schema"


task default: %i[]

# Regenerate all SXL JSON Schemas.
# Warning: This will destructively override all relevant files. Any changes will be lost!
task :regenerate do
  puts "Regenerating SXL JSON Schemas:"
  Dir.glob('schemas/tlc/*/sxl.yaml').each do |path|
    puts "  #{File.dirname(path)}"
    sxl = RSMP::Convert::Import::YAML.read path
    RSMP::Convert::Export::JSONSchema.write sxl, File.dirname(path)
  end
end
