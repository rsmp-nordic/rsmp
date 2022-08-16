# Import SXL from YAML format

require 'yaml'
require 'json'
require 'fileutils'

module RSMP
  module Convert
    module Import
      module YAML

        def self.read path
          convert ::YAML.load_file(path)
        end

        def self.parse str
          convert ::YAML.load(str)
        end

        def self.convert yaml
          sxl = {
            meta: {},
            alarms: {},
            statuses: {},
            commands: {}
          }

          sxl[:meta] = yaml['meta']

          yaml['objects'].each_pair do |type,object|
            object["alarms"].each { |id,item| sxl[:alarms][id] = item } if object["alarms"]
            object["statuses"].each { |id,item| sxl[:statuses][id] = item } if object["statuses"]
            object["commands"].each { |id,item| sxl[:commands][id] = item } if object["commands"]
          end
          sxl
        end
      end

    end
  end
end