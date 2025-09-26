require_relative 'base_options'

module RSMP
  module Options
    # Configuration options specific to RSMP Supervisor instances
    class SupervisorOptions < BaseOptions
      
      # Convenience accessors for commonly used configuration values
      def port
        get('port')
      end

      def port=(value)
        set('port', value)
      end

      def ips
        get('ips')
      end

      def site_id
        get('site_id')
      end

      def guest_settings
        get('guest')
      end

      def sites_settings
        get('sites')
      end

      def core_version
        get('guest.core_version')
      end

      protected

      def defaults
        {
          'port' => 12111,
          'ips' => 'all',
          'guest' => {
            'sxl' => 'tlc',
            'intervals' => {
              'timer' => 1,
              'watchdog' => 1
            },
            'timeouts' => {
              'watchdog' => 2,
              'acknowledgement' => 2
            }
          }
        }
      end

      def schema
        {
          "type" => "object",
          "properties" => {
            "port" => {
              "type" => "integer",
              "minimum" => 1,
              "maximum" => 65535
            },
            "ips" => {
              "oneOf" => [
                { "type" => "string", "enum" => ["all"] },
                {
                  "type" => "array",
                  "items" => {
                    "type" => "string",
                    "format" => "ipv4"
                  }
                }
              ]
            },
            "site_id" => {
              "type" => "string",
              "pattern" => "^[A-Za-z0-9+=-]+$"
            },
            "guest" => {
              "type" => "object",
              "properties" => {
                "sxl" => {
                  "type" => "string"
                },
                "core_version" => {
                  "type" => "string"
                },
                "intervals" => {
                  "type" => "object",
                  "properties" => {
                    "timer" => {
                      "type" => "number",
                      "minimum" => 0
                    },
                    "watchdog" => {
                      "type" => "number",
                      "minimum" => 0
                    }
                  },
                  "additionalProperties" => false
                },
                "timeouts" => {
                  "type" => "object",
                  "properties" => {
                    "watchdog" => {
                      "type" => "number",
                      "minimum" => 0
                    },
                    "acknowledgement" => {
                      "type" => "number",
                      "minimum" => 0
                    }
                  },
                  "additionalProperties" => false
                }
              },
              "required" => ["sxl"],
              "additionalProperties" => true
            },
            "sites" => {
              "type" => "object",
              "patternProperties" => {
                ".*" => {
                  "type" => "object",
                  "properties" => {
                    "sxl" => {
                      "type" => "string"
                    },
                    "core_version" => {
                      "type" => "string"
                    },
                    "intervals" => {
                      "type" => "object",
                      "properties" => {
                        "timer" => {
                          "type" => "number",
                          "minimum" => 0
                        },
                        "watchdog" => {
                          "type" => "number",
                          "minimum" => 0
                        }
                      },
                      "additionalProperties" => false
                    },
                    "timeouts" => {
                      "type" => "object",
                      "properties" => {
                        "watchdog" => {
                          "type" => "number",
                          "minimum" => 0
                        },
                        "acknowledgement" => {
                          "type" => "number",
                          "minimum" => 0
                        }
                      },
                      "additionalProperties" => false
                    }
                  },
                  "additionalProperties" => true
                }
              }
            }
          },
          "required" => ["port", "guest"],
          "additionalProperties" => true
        }
      end

      def custom_validations
        errors = []

        return errors unless defined?(RSMP::Schema)

        # Validate guest SXL settings
        guest = get('guest')
        if guest
          sxl = guest['sxl']
          if sxl
            begin
              RSMP::Schema.find_schemas!(sxl)
            rescue RSMP::Schema::UnknownSchemaError => e
              errors << "Invalid guest SXL configuration: #{e.message}"
            end
          end

          # Validate guest core version if specified
          core_ver = guest['core_version']
          if core_ver && !RSMP::Schema.core_versions.include?(core_ver)
            errors << "Unknown guest core version: #{core_ver}. Available versions: #{RSMP::Schema.core_versions.join(', ')}"
          end
        end

        # Validate site-specific SXL settings
        sites = get('sites')
        if sites
          sites.each do |site_id, settings|
            next unless settings

            sxl = settings['sxl']
            if sxl
              begin
                RSMP::Schema.find_schemas!(sxl)
              rescue RSMP::Schema::UnknownSchemaError => e
                errors << "Invalid SXL configuration for site '#{site_id}': #{e.message}"
              end
            else
              errors << "Configuration error for site '#{site_id}': No SXL specified"
            end

            # Validate site core version if specified
            core_ver = settings['core_version']
            if core_ver && !RSMP::Schema.core_versions.include?(core_ver)
              errors << "Unknown core version for site '#{site_id}': #{core_ver}. Available versions: #{RSMP::Schema.core_versions.join(', ')}"
            end
          end
        end

        errors
      end
    end
  end
end