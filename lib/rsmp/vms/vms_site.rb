module RSMP
  module VMS
    # Simulates a Traffic Light Controller Site
    class VMSSite < Site
      attr_accessor :main, :signal_plans

      def initialize options={}
        # setup options before calling super initializer,
        # since build of components depend on options
        @sxl = 'vms'
        @security_codes = options[:site_settings]['security_codes']
        @interval = options[:site_settings].dig('intervals','timer') || 1

        super options

        unless main
          raise ConfigurationError.new "VMS must have a main component"
        end
      end

      def site_type_name
        'VMS (Variable Message Sign)'
      end

      def start
        super
      end

      def stop_subtasks
        super
      end

      def build_component id:, type:, settings:{}
        component = 
        case type
        when 'main'
          VMSController.new node: self,
            id: id,
            ntsOId: settings['ntsOId'],
            xNId: settings['xNId']            
          end
      end

      def verify_security_code level, code
        raise ArgumentError.new("Level must be 1-2, got #{level}") unless (1..2).include?(level)
        if @security_codes[level] != code
          raise MessageRejected.new("Wrong security code for level #{level}")
        end
      end

      def self.to_rmsp_bool bool
        if bool
          'True'
        else
          'False'
        end
      end

      def self.from_rsmp_bool str
        str == 'True'
      end

      def self.make_status value, q='recent'
        case value
        when true, false
          return to_rmsp_bool(value), q
        else
          return value, q
        end
      end
    end
  end
end