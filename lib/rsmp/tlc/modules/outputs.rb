# frozen_string_literal: true

module RSMP
  module TLC
    module Modules
      # Output management for traffic controller
      # Handles output status queries and forcing
      module Outputs
        # M0020 - Force output
        def handle_m0020(arg, _options = {})
          @node.verify_security_code 2, arg['securityCode']
        end

        # S0004 - Output status
        def handle_s0004(_status_code, status_name = nil, _options = {})
          case status_name
          when 'outputstatus', 'extendedoutputstatus'
            TrafficControllerSite.make_status 0
          end
        end

        # S0030 - Forced output status
        def handle_s0030(_status_code, status_name = nil, _options = {})
          case status_name
          when 'status'
            TrafficControllerSite.make_status ''
          end
        end
      end
    end
  end
end
