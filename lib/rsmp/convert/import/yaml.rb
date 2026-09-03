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
          merge_components(sxl, component_definitions(yaml))
          sxl
        end

        def self.build_empty_sxl
          { meta: {}, alarms: {}, statuses: {}, commands: {} }
        end

        def self.component_definitions(yaml)
          yaml.fetch('components') { yaml.fetch('objects') }
        end

        def self.merge_components(sxl, components)
          components.each_pair do |_type, component|
            merge_component_items(sxl, component)
          end
        end

        def self.merge_component_items(sxl, component)
          component['alarms']&.each { |id, item| sxl[:alarms][id] = item }
          component['statuses']&.each { |id, item| sxl[:statuses][id] = item }
          component['commands']&.each { |id, item| sxl[:commands][id] = item }
        end
      end
    end
  end
end
