module RSMP
  module SXL
    module Processing
      # Indexes locally available SXL definitions by name and exact version.
      class Catalogue
        def initialize(paths = [])
          @documents = Hash.new { |hash, key| hash[key] = {} }
          Array(paths).each { |path| add_path(path) }
        end

        def add_path(path)
          expanded_path = File.expand_path(path)
          raise Error, "SXL source #{path} not found" unless File.exist?(expanded_path)

          if File.directory?(expanded_path)
            pattern = File.join(expanded_path, '**', '{sxl.yaml,sxl.yml}')
            files = Dir.glob(pattern)
            raise Error, "No sxl.yaml or sxl.yml files found under #{path}" if files.empty?

            files.each { |file| add_file(file) }
          else
            add_file(expanded_path)
          end
          self
        end

        def add_document(document)
          existing = @documents[document.name][document.version_string]
          if existing && existing.path != document.path
            raise Error,
                  "Duplicate SXL #{document.name} #{document.version_string} in #{existing.path} and #{document.path}"
          end

          @documents[document.name][document.version_string] = document
          document
        end

        def candidates(name, requirements = [])
          versions = @documents.fetch(name, {}).values.sort_by(&:version).reverse
          versions.select do |document|
            requirements.all? { |requirement| requirement.satisfied_by?(document.version) }
          end
        end

        def versions(name)
          @documents.fetch(name, {}).values.map(&:version_string).sort_by { |version| Gem::Version.new(version) }
        end

        def fetch(name, version)
          @documents.fetch(name, {})[version.to_s]
        end

        private

        def add_file(path)
          add_document(Document.load(path))
        end
      end
    end
  end
end
