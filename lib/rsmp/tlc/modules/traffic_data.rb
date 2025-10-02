# frozen_string_literal: true

module RSMP
  module TLC
    module Modules
      # Traffic data collection and user login tracking
      # Handles traffic counting data and user authentication status
      module TrafficData
        # S0091 - User login status
        def handle_s0091(_status_code, status_name = nil, _options = {})
          case status_name
          when 'user'
            TrafficControllerSite.make_status ''
          when 'status'
            TrafficControllerSite.make_status TrafficControllerSite.to_rmsp_bool(false)
          end
        end

        # S0092 - User login sensitivity
        def handle_s0092(_status_code, status_name = nil, _options = {})
          case status_name
          when 'user'
            TrafficControllerSite.make_status ''
          when 'status'
            TrafficControllerSite.make_status TrafficControllerSite.to_rmsp_bool(false)
          end
        end

        # S0205 - Start of signal group green
        def handle_s0205(_status_code, status_name = nil, _options = {})
          case status_name
          when 'start'
            TrafficControllerSite.make_status clock.to_s
          when 'P', 'PS', 'L', 'LS', 'B', 'SP', 'MC', 'C', 'F'
            TrafficControllerSite.make_status 0
          end
        end

        # S0206 - Expected end of signal group green
        def handle_s0206(_status_code, status_name = nil, _options = {})
          case status_name
          when 'start'
            TrafficControllerSite.make_status clock.to_s
          when 'P', 'PS', 'L', 'LS', 'B', 'SP', 'MC', 'C', 'F'
            TrafficControllerSite.make_status 0
          end
        end

        # S0207 - Predicted time to green
        def handle_s0207(_status_code, status_name = nil, _options = {})
          case status_name
          when 'minTime', 'maxTime', 'likelyTime'
            TrafficControllerSite.make_status clock.to_s
          when 'P', 'PS', 'L', 'LS', 'B', 'SP', 'MC', 'C', 'F'
            TrafficControllerSite.make_status 0
          end
        end

        # S0208 - Predicted time to red
        def handle_s0208(_status_code, status_name = nil, _options = {})
          case status_name
          when 'start'
            TrafficControllerSite.make_status clock.to_s
          when 'P', 'PS', 'L', 'LS', 'B', 'SP', 'MC', 'C', 'F'
            TrafficControllerSite.make_status 0
          end
        end
      end
    end
  end
end
