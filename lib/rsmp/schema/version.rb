module RSMP
  # Provides JSON Schema validation for RSMP messages across core and SXL versions.
  module Schema
    STRICT_VERSION_PATTERN = /\A(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\z/
    LEGACY_SHORT_VERSION_PATTERN = /\A(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\z/

    # Return the schema version for a supported Core version string.
    # Before Core 3.3, some releases used a two-part version on the wire.
    # Only accept such a version when adding .0 identifies a known legacy
    # schema unambiguously. Core 3.3 and later require all three parts.
    def self.normalize_core_version(version)
      return unless version.is_a?(String)
      return version if core_versions.include? version
      return unless LEGACY_SHORT_VERSION_PATTERN.match? version

      normalized = "#{version}.0"
      return unless core_versions.include? normalized
      return unless Gem::Version.new(normalized) < Gem::Version.new('3.3.0')

      normalized
    end

    def self.strict_version?(version)
      version.is_a?(String) && STRICT_VERSION_PATTERN.match?(version)
    end
  end
end
