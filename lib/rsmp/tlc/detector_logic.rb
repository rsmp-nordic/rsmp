module RSMP
  module TLC
    class DetectorLogic < Component
      attr_reader :forced, :value

      def initialize node:, id:
        super node: node, id: id, grouped: false
        @forced = 0
        @value = 0
      end

      def get_status code, name=nil, options={}
        case code
        when 'S0201', 'S0202', 'S0203', 'S0204'
          return send("handle_#{code.downcase}", code, name)
        else
          raise InvalidMessage.new "unknown status code #{code}"
        end
      end

      def handle_s0201 status_code, status_name=nil, options={}
        case status_name
        when 'starttime'
          TrafficControllerSite.make_status @node.clock.to_s
        when 'vehicles'
          TrafficControllerSite.make_status 0
        end
      end

      def handle_s0202 status_code, status_name=nil, options={}
        case status_name
        when 'starttime'
          TrafficControllerSite.make_status @node.clock.to_s
        when 'speed'
          TrafficControllerSite.make_status 0
        end
      end

      def handle_s0203 status_code, status_name=nil, options={}
        case status_name
        when 'starttime'
          TrafficControllerSite.make_status @node.clock.to_s
        when 'occupancy'
          TrafficControllerSite.make_status 0
        end
      end

      def handle_s0204 status_code, status_name=nil, options={}
        case status_name
        when 'starttime'
          TrafficControllerSite.make_status @node.clock.to_s
        when 'P'
          TrafficControllerSite.make_status 0
        when 'PS'
          TrafficControllerSite.make_status 0
        when 'L'
          TrafficControllerSite.make_status 0
        when 'LS'
          TrafficControllerSite.make_status 0
        when 'B'
          TrafficControllerSite.make_status 0
        when 'SP'
          TrafficControllerSite.make_status 0
        when 'MC'
          TrafficControllerSite.make_status 0
        when 'C'
          TrafficControllerSite.make_status 0
        when 'F'
          TrafficControllerSite.make_status 0
        end
      end

      def handle_command command_code, arg, options={}
        case command_code
        when 'M0008'
          handle_m0008 arg
        else
          raise UnknownCommand.new "Unknown command #{command_code}"
        end
      end

      def handle_m0008 arg, options={}
        @node.verify_security_code 2, arg['securityCode']
        status = arg['status']=='True'
        mode = arg['mode']=='True'
        force_detector_logic status, mode
        arg
      end

      def force_detector_logic forced, value
        @forced = forced
        @value = value
        if @forced
          log "Forcing to #{value}", level: :info
        else
          log "Releasing", level: :info
        end
      end
    end
  end
end