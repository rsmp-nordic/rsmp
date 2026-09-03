require 'psych'

module RSMP
  module SXL
    module Processing
      # A validated SXL YAML document with a normalized component structure.
      class Document
        NAME = %r{\A[a-z0-9][a-z0-9_/-]*\z}
        PREFIX = %r{\A[a-zA-Z0-9_/-]+/\z}
        MESSAGE_KINDS = %w[alarms statuses commands].freeze

        SymbolDefinition = Struct.new(:id, :kind, :location, keyword_init: true)

        attr_reader :path, :data, :name, :version, :version_string, :minimum_core_version,
                    :dependencies, :component_types, :message_codes

        def self.load(path)
          expanded_path = File.expand_path(path)
          raise Error, "SXL source #{path} not found" unless File.exist?(expanded_path)
          raise Error, "SXL source #{path} is not a file" unless File.file?(expanded_path)

          parse(File.read(expanded_path, encoding: 'UTF-8'), path: expanded_path)
        rescue EncodingError => e
          raise Error, "Cannot read SXL source #{path}: #{e.message}"
        end

        def self.parse(source, path: '(SXL source)')
          data = Psych.safe_load(source, permitted_classes: [], permitted_symbols: [], aliases: false)
          new(path: path, data: data)
        rescue Psych::Exception => e
          raise Error, "Cannot read SXL source #{path}: #{e.message}"
        end

        def self.validate_name!(value, label: 'SXL name')
          return value if value.is_a?(String) && NAME.match?(value)

          raise Error, "Invalid #{label} #{value.inspect}"
        end

        def initialize(path:, data:)
          @path = path
          @data = normalize_document(require_hash(data, 'document'))
          read_metadata
          read_dependencies
          read_symbols
        rescue Error => e
          raise Error, "#{path}: #{e.message}"
        end

        private

        def normalize_document(document)
          components = component_definitions(document)
          document.except('objects').merge('components' => components)
        end

        def component_definitions(document)
          if document.key?('components') && document.key?('objects')
            raise Error, 'Invalid document; use either components or objects, not both'
          end

          key = document.key?('components') ? 'components' : 'objects'
          require_hash(document[key], key)
        end

        def read_metadata
          meta = require_hash(data['meta'], 'meta')
          @name = self.class.validate_name!(meta['name'])
          @version_string = meta['version'].to_s
          @version = VersionRequirement.exact_version(meta['version'], label: 'SXL version')
          @minimum_core_version = read_minimum_core_version(meta)
          @prefix = data['prefix']
          validate_prefix!
        end

        def read_minimum_core_version(meta)
          minimum = meta['minimum_core_version']
          return unless minimum

          VersionRequirement.exact_version(minimum, label: 'minimum Core version')
        end

        def validate_prefix!
          return if @prefix.nil? || (@prefix.is_a?(String) && PREFIX.match?(@prefix))

          raise Error, "Invalid SXL prefix #{@prefix.inspect}; it must end with /"
        end

        def read_dependencies
          dependency_data = data['dependencies'] || {}
          require_hash(dependency_data, 'dependencies')
          @dependencies = dependency_data.to_h do |dependency_name, requirement|
            self.class.validate_name!(dependency_name, label: 'dependency name')
            unless requirement.is_a?(String)
              raise Error, "Invalid requirement for #{dependency_name.inspect}; expected a string"
            end

            [dependency_name, VersionRequirement.new(requirement)]
          end
        end

        def read_symbols
          components = data['components']
          @component_types = []
          @message_codes = []
          seen_components = {}
          seen_messages = {}

          components.each_pair do |component_id, component|
            component_id = require_identifier(component_id, 'component type')
            full_component_id = prefixed(component_id)
            ensure_unique!(seen_components, full_component_id, 'component type')
            @component_types << SymbolDefinition.new(id: full_component_id, kind: :component,
                                                     location: component_id)
            read_component_messages(component_id, component, seen_messages)
          end
        end

        def read_component_messages(component_id, component, seen_messages)
          component = require_hash(component, "component #{component_id.inspect}")
          MESSAGE_KINDS.each do |kind|
            messages = component[kind] || {}
            require_hash(messages, "#{kind} for component #{component_id.inspect}")
            messages.each_key do |code|
              code = require_identifier(code, 'message code')
              full_code = prefixed(code)
              ensure_unique!(seen_messages, full_code, 'message code')
              @message_codes << SymbolDefinition.new(id: full_code, kind: kind.delete_suffix('s').to_sym,
                                                     location: "#{component_id}/#{kind}/#{code}")
            end
          end
        end

        def require_hash(value, label)
          return value if value.is_a?(Hash)

          raise Error, "Invalid #{label}; expected a mapping"
        end

        def require_identifier(value, label)
          return value if value.is_a?(String) && !value.empty?

          raise Error, "Invalid #{label} #{value.inspect}; expected a non-empty string"
        end

        def prefixed(identifier)
          "#{@prefix}#{identifier}"
        end

        def ensure_unique!(seen, identifier, label)
          raise Error, "Duplicate #{label} #{identifier.inspect}" if seen[identifier]

          seen[identifier] = true
        end
      end
    end
  end
end
