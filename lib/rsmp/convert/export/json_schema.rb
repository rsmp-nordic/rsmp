# Export SXL to JSON Schema format

require 'yaml'
require 'json'
require 'fileutils'

require_relative 'json_schema/values'
require_relative 'json_schema/items'
require_relative 'json_schema/outputs'

module RSMP
  module Convert
    # Handles exporting SXL definitions.
    module Export
      # Converts SXL definitions to JSON Schema files.
      module JSONSchema
        JSON_OPTIONS = {
          array_nl: "\n",
          object_nl: "\n",
          indent: '  ',
          space_before: ' ',
          space: ' '
        }.freeze

        def self.output_json(item)
          JSON.generate(item, JSON_OPTIONS)
        end

        def self.minimum_core_version(sxl)
          sxl.dig(:meta, 'minimum_core_version') || RSMP::Schema.latest_core_version
        end

        # Path to definitions.json for the fallback bundled core schema version
        def self.definitions_source(sxl)
          version = minimum_core_version(sxl)
          path = File.expand_path("../../../../schemas/core/#{version}/definitions.json", __dir__)
          raise "Missing core definitions for RSMP #{version}" unless File.exist?(path)

          path
        end

        # generate the json schema from a string containing yaml
        def self.generate(sxl)
          out = {}
          output_root out, sxl[:meta]
          output_alarms out, sxl[:alarms]
          output_statuses out, sxl[:statuses]
          output_commands out, sxl[:commands]
          output_sxl_index out, sxl
          out
        end

        # convert yaml to json schema and write files to a folder
        def self.write(sxl, folder)
          out = generate sxl
          out.each_pair do |relative_path, str|
            path = File.join(folder, relative_path)
            FileUtils.mkdir_p File.dirname(path)
            File.open(path, 'w+') { |file| file.puts str }
          end
          # Copy definitions.json so each version folder is self-contained
          defs_dest = File.join(folder, 'defs', 'definitions.json')
          FileUtils.mkdir_p File.dirname(defs_dest)
          source = definitions_source(sxl)
          FileUtils.cp source, defs_dest
        end
      end
    end
  end
end
