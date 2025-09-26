# RSMP Configuration Options
# 
# Provides structured configuration handling for RSMP components with:
# - Hierarchical defaults
# - JSON schema validation  
# - Type-safe accessors
# - File-based configuration loading

require_relative 'options/base_options'
require_relative 'options/site_options'
require_relative 'options/supervisor_options'

module RSMP
  module Options
    # Factory method to create appropriate options instance
    def self.create(type, config = {})
      case type.to_sym
      when :site
        SiteOptions.new(config)
      when :supervisor
        SupervisorOptions.new(config)
      else
        raise ArgumentError, "Unknown options type: #{type}"
      end
    end
  end
end