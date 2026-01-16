# Import SXL from YAML format

require 'yaml'
require 'json'
require 'fileutils'

module RSMP
  module Convert
    module Import
      # Importer for SXL in YAML format.
      module YAML
        def self.read(path)
          convert ::YAML.load_file(path)
        end

        def self.parse(str)
          convert ::YAML.load(str)
        end

        def self.convert(yaml)
          sxl = build_empty_sxl
          sxl[:meta] = yaml['meta']
          merge_objects(sxl, yaml['objects'])
          sxl
        end

        def self.build_empty_sxl
          { meta: {}, alarms: {}, statuses: {}, commands: {} }
        end

        def self.merge_objects(sxl, objects)
          objects.each_pair do |_type, object|
            merge_object_items(sxl, object)
          end
        end

        def self.merge_object_items(sxl, object)
          object['alarms']&.each { |id, item| sxl[:alarms][id] = item }
          object['statuses']&.each { |id, item| sxl[:statuses][id] = item }
          object['commands']&.each { |id, item| sxl[:commands][id] = item }
        end
      end
    end
  end
end
