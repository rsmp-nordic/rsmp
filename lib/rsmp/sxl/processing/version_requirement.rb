require 'rubygems'

module RSMP
  module SXL
    module Processing
      # Parses the version requirement syntax defined by RSMP Core.
      class VersionRequirement
        EXACT_VERSION = /\A(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)\z/
        PARTIAL_VERSION = /\A(0|[1-9]\d*)\.(0|[1-9]\d*)(?:\.(0|[1-9]\d*))?\z/
        CLAUSE = /\A(~|>=|<=|>|<)?\s*(\d+(?:\.\d+){1,2})\z/

        attr_reader :source

        def self.exact_version(value, label: 'version')
          string = value.to_s
          unless EXACT_VERSION.match?(string)
            raise Error, "Invalid #{label} #{value.inspect}; expected MAJOR.MINOR.PATCH"
          end

          Gem::Version.new(string)
        end

        def initialize(source)
          @source = source.to_s
          @predicates = parse(@source)
        end

        def satisfied_by?(version)
          version = self.class.exact_version(version) unless version.is_a?(Gem::Version)
          @predicates.all? { |predicate| predicate.call(version) }
        end

        private

        def parse(source)
          raise Error, 'Version requirement cannot be empty' if source.strip.empty?

          source.split(/\s+and\s+/).map { |clause| parse_clause(clause.strip) }
        end

        def parse_clause(clause)
          match = CLAUSE.match(clause)
          raise Error, "Invalid version requirement #{source.inspect}" unless match

          operator = match[1]
          version_string = match[2]
          return compatible_predicate(version_string) if operator == '~'

          version = self.class.exact_version(version_string, label: 'requirement version')
          comparison_predicate(operator || '=', version)
        end

        def compatible_predicate(version_string)
          match = PARTIAL_VERSION.match(version_string)
          raise Error, "Invalid compatibility requirement #{source.inspect}" unless match

          major, minor, patch = match.captures.map { |part| part&.to_i }
          return major_zero_predicate(major, minor, patch) if major.zero?

          lower = Gem::Version.new("#{major}.#{minor}.#{patch || 0}")
          upper = Gem::Version.new("#{major + 1}.0.0")
          ->(version) { version >= lower && version < upper }
        end

        def major_zero_predicate(major, minor, patch)
          unless patch
            raise Error, "Major-zero compatibility requirement #{source.inspect} must include an exact patch version"
          end

          exact = Gem::Version.new("#{major}.#{minor}.#{patch}")
          ->(version) { version == exact }
        end

        def comparison_predicate(operator, expected)
          case operator
          when '=' then ->(version) { version == expected }
          when '>' then ->(version) { version > expected }
          when '>=' then ->(version) { version >= expected }
          when '<' then ->(version) { version < expected }
          when '<=' then ->(version) { version <= expected }
          end
        end
      end
    end
  end
end
