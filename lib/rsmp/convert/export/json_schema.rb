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

        # Default path to definitions.json bundled with the gem's core schemas
        DEFINITIONS_SOURCE = File.expand_path('../../../../schemas/core/3.1.2/definitions.json', __dir__)

        # generate the json schema from a string containing yaml
        def self.generate(sxl)
          out = {}
          output_root out, sxl[:meta]
          output_alarms out, sxl[:alarms]
          output_statuses out, sxl[:statuses]
          output_commands out, sxl[:commands]
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
          FileUtils.cp DEFINITIONS_SOURCE, defs_dest if File.exist?(DEFINITIONS_SOURCE)
        end
      end
    end
  end
end
