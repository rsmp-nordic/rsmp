# Import SXL from YAML format

require 'yaml'
require 'json'
require 'fileutils'

module RSMP
  module Convert
    module Import
      module YAML
        def self.read(path)
          convert ::YAML.load_file(path)
        end

        def self.parse(str)
          convert ::YAML.load(str)
        end

        def self.convert(yaml)
          {
            meta: yaml['meta'],
            alarms: collect_items(yaml, 'alarms'),
            statuses: collect_items(yaml, 'statuses'),
            commands: collect_items(yaml, 'commands')
          }
        end

        def self.collect_items(yaml, key)
          items = {}
          yaml.fetch('objects', {}).each_value do |object|
            append_items(items, object, key)
          end
          items
        end

        def self.append_items(items, object, key)
          object[key]&.each_pair { |id, item| items[id] = item }
        end
      end
    end
  end
end
