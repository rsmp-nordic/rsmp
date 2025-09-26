module RSMP
  module TLC
    module TrafficControllerExtensions
      module Status
        module System
          module Traffic
            def handle_s0205(_status_code, status_name = nil, _options = {})
              case status_name
              when 'start'
                TrafficControllerSite.make_status clock.to_s
              when 'vehicles'
                TrafficControllerSite.make_status 0
              end
            end

            def handle_s0206(_status_code, status_name = nil, _options = {})
              case status_name
              when 'start'
                TrafficControllerSite.make_status clock.to_s
              when 'speed'
                TrafficControllerSite.make_status 0
              end
            end

            def handle_s0207(_status_code, status_name = nil, _options = {})
              case status_name
              when 'start'
                TrafficControllerSite.make_status clock.to_s
              when 'occupancy'
                values = [-1, 0, 50, 100]
                output = @detector_logics.each_with_index.map { |_dl, i| values[i % values.size] }.join(',')
                TrafficControllerSite.make_status output
              end
            end

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
  end
end
