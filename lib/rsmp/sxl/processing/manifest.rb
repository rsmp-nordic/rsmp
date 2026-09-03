require 'date'
require 'psych'
require 'time'

module RSMP
  module SXL
    module Processing
      # Creates and verifies deterministic SXL manifests.
      module Manifest
        TOP_LEVEL_KEYS = %w[meta sxls].freeze
        META_KEYS = %w[created_at created_by format].freeze

        def self.create(documents, format:, now: Time.now)
          validate_documents!(documents, format)
          {
            'meta' => {
              'created_at' => now.utc.iso8601,
              'created_by' => "rsmp v#{RSMP::VERSION}",
              'format' => format.to_s
            },
            'sxls' => NaturalSort.sort(documents.map(&:name)).to_h do |name|
              document = documents.find { |candidate| candidate.name == name }
              [name, document.version_string]
            end
          }
        end

        def self.dump(manifest)
          Psych.safe_dump(manifest, permitted_classes: [], aliases: false, line_width: -1)
        end

        def self.load(path)
          raise Error, "Manifest #{path} not found" unless File.exist?(path)
          raise Error, "Manifest #{path} is not a file" unless File.file?(path)

          parse(File.read(path, encoding: 'UTF-8'), path: path)
        rescue EncodingError => e
          raise Error, "Cannot read manifest #{path}: #{e.message}"
        end

        def self.parse(source, path: '(manifest)')
          Psych.safe_load(source, permitted_classes: [Date, Time], permitted_symbols: [], aliases: false)
        rescue Psych::Exception => e
          raise Error, "Cannot read manifest #{path}: #{e.message}"
        end

        def self.verify!(manifest, catalogue)
          meta, sxls = validate_shape!(manifest)
          documents = load_documents!(sxls, catalogue)
          validate_dependency_closure!(documents, sxls)
          validate_documents!(documents, meta['format'])
          documents
        end

        def self.validate_documents!(documents, format)
          format_version = VersionRequirement.exact_version(format, label: 'manifest format')
          documents.each do |document|
            next unless document.minimum_core_version && document.minimum_core_version > format_version

            raise Error,
                  "SXL #{document.name} #{document.version_string} requires Core " \
                  "#{document.minimum_core_version}, newer than manifest format #{format}"
          end
          cycle = DependencyGraph.cycle(documents)
          raise Error, "Cyclic dependency #{cycle.join(' -> ')}" if cycle

          ConflictChecker.check!(documents)
        end

        def self.validate_shape!(manifest)
          raise Error, 'Invalid manifest; expected a mapping' unless manifest.is_a?(Hash)

          reject_unknown_keys!(manifest, TOP_LEVEL_KEYS, 'manifest')

          meta = manifest['meta']
          sxls = manifest['sxls']
          raise Error, 'Invalid manifest meta; expected a mapping' unless meta.is_a?(Hash)
          raise Error, 'Invalid manifest sxls; expected a non-empty mapping' unless sxls.is_a?(Hash) && !sxls.empty?

          reject_unknown_keys!(meta, META_KEYS, 'manifest meta')
          validate_metadata!(meta)
          validate_sxls!(sxls)
          [meta, sxls]
        end

        def self.validate_metadata!(meta)
          missing = META_KEYS.reject { |key| meta.key?(key) }
          raise Error, "Manifest meta is missing #{missing.join(', ')}" unless missing.empty?

          Time.iso8601(meta['created_at'].to_s)
          unless meta['created_by'].is_a?(String) && !meta['created_by'].empty?
            raise Error, 'Manifest created_by must be a non-empty string'
          end

          VersionRequirement.exact_version(meta['format'], label: 'manifest format')
        rescue ArgumentError
          raise Error, 'Manifest created_at must be an ISO 8601 timestamp'
        end

        def self.validate_sxls!(sxls)
          sxls.each_pair do |name, version|
            Document.validate_name!(name)
            VersionRequirement.exact_version(version, label: "version for #{name}")
          end
          expected_order = NaturalSort.sort(sxls.keys)
          return if sxls.keys == expected_order

          raise Error, 'Manifest SXLs are not in natural name order'
        end

        def self.load_documents!(sxls, catalogue)
          sxls.map do |name, version|
            document = catalogue.fetch(name, version)
            raise Error, "SXL #{name} #{version} is not available from the supplied sources" unless document

            document
          end
        end

        def self.validate_dependency_closure!(documents, sxls)
          documents.each do |document|
            document.dependencies.each_pair do |name, requirement|
              version = sxls[name]
              raise Error, "Manifest is missing dependency #{name} required by #{document.name}" unless version
              next if requirement.satisfied_by?(version)

              raise Error,
                    "Manifest dependency #{name} #{version} does not satisfy #{requirement.source} " \
                    "required by #{document.name}"
            end
          end
        end

        def self.reject_unknown_keys!(hash, expected, label)
          unknown = hash.keys - expected
          raise Error, "Unknown #{label} key(s): #{unknown.join(', ')}" unless unknown.empty?
        end

        private_class_method :validate_shape!, :validate_metadata!, :validate_sxls!, :load_documents!,
                             :validate_dependency_closure!, :reject_unknown_keys!
      end
    end
  end
end
