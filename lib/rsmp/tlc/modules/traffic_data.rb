module RSMP
  module TLC
    module Modules
      # Traffic counting data collection for TLC
      # Handles aggregate traffic counting status for all detectors
      module TrafficData
        # S0205 - Traffic Counting: Number of vehicles (aggregate)
        def handle_s0205(_status_code, status_name = nil, _options = {})
          case status_name
          when 'start'
            TrafficControllerSite.make_status clock.to_s
          when 'vehicles'
            TrafficControllerSite.make_status 0
          end
        end

        # S0206 - Traffic Counting: Vehicle speed (aggregate)
        def handle_s0206(_status_code, status_name = nil, _options = {})
          case status_name
          when 'start'
            TrafficControllerSite.make_status clock.to_s
          when 'speed'
            TrafficControllerSite.make_status 0
          end
        end

        # S0207 - Traffic Counting: Occupancy (aggregate)
        def handle_s0207(_status_code, status_name = nil, _options = {})
          case status_name
          when 'start'
            TrafficControllerSite.make_status clock.to_s
          when 'occupancy'
            TrafficControllerSite.make_status 0
          end
        end

        # S0208 - Traffic Counting: Number of vehicles by classification (aggregate)
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
