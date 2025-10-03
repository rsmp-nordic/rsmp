# frozen_string_literal: true

module RSMP
  module TLC
    module Modules
      # Detector logic management for traffic controller
      # Handles detector logic status queries and forcing
      module DetectorLogics
        def add_detector_logic(logic)
          @detector_logics << logic
        end

        # M0021 - Force detector logic
        def handle_m0021(arg, _options = {})
          @node.verify_security_code 2, arg['securityCode']
        end

        # S0002 - Detector logic status
        def handle_s0002(_status_code, status_name = nil, _options = {})
          case status_name
          when 'detectorlogicstatus'
            TrafficControllerSite.make_status @detector_logics.map { |dl| bool_to_digit(dl.value) }.join
          end
        end

        # S0016 - Number of detector logics
        def handle_s0016(_status_code, status_name = nil, _options = {})
          case status_name
          when 'number'
            TrafficControllerSite.make_status @detector_logics.size
          end
        end

        # S0021 - Detector logic forcing status
        def handle_s0021(_status_code, status_name = nil, _options = {})
          case status_name
          when 'detectorlogics'
            TrafficControllerSite.make_status @detector_logics.map { |logic| bool_to_digit(logic.forced) }.join
          end
        end

        # S0031 - Trigger level sensitivity for loop detector
        def handle_s0031(_status_code, status_name = nil, _options = {})
          case status_name
          when 'status'
            TrafficControllerSite.make_status ''
          end
        end
      end
    end
  end
end
