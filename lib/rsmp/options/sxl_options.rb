module RSMP
  # Configuration and internal representation of supported SXL versions.
  module SxlOptions
    private

    def normalize_sxls(value)
      case value
      when Hash
        value.map do |name, details|
          normalize_sxl_item(name.to_s, details)
        end
      when Array
        value.map { |item| normalize(item) }
      else
        value
      end
    end

    def normalize_config_sxls(value)
      raise RSMP::ConfigurationError, 'sxls must be a hash of SXL names to versions' unless value.is_a?(Hash)

      value.each_with_object({}) do |(name, details), memo|
        validate_sxl_versions!(name, details)
        memo[name.to_s] = details
      end
    end

    def validate_sxl_versions!(name, details)
      versions = details.is_a?(Array) ? details : [details]
      if versions.empty? || versions.any? { |version| !version.is_a?(String) }
        raise RSMP::ConfigurationError, "sxls/#{name} must be a version string or a non-empty list of version strings"
      end

      valid = versions.all? do |version|
        RSMP::Schema.strict_version?(version) || (details.is_a?(String) && version == 'latest')
      end
      raise RSMP::ConfigurationError, "sxls/#{name} must use MAJOR.MINOR.PATCH" unless valid
      return if versions.uniq == versions

      raise RSMP::ConfigurationError, "sxls/#{name} must not contain duplicate versions"
    end

    def normalize_sxl_item(name, details)
      case details
      when Array
        { 'name' => name, 'version' => details.first, 'versions' => details.dup }
      when Hash
        raise RSMP::ConfigurationError, "sxls/#{name} must be a version string"
      when nil
        { 'name' => name }
      else
        { 'name' => name, 'version' => details.to_s }
      end
    end
  end
end
