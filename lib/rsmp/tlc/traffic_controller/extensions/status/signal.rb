module RSMP
  module TLC
    module TrafficControllerExtensions
      module Status
        module Signal
          def handle_s0001(_status_code, status_name = nil, _options = {})
            case status_name
            when 'signalgroupstatus'
              TrafficControllerSite.make_status format_signal_group_status
            when 'cyclecounter', 'basecyclecounter'
              TrafficControllerSite.make_status @cycle_counter.to_s
            when 'stage'
              TrafficControllerSite.make_status 0.to_s
            end
          end

          def handle_s0002(_status_code, status_name = nil, _options = {})
            case status_name
            when 'detectorlogicstatus'
              TrafficControllerSite.make_status @detector_logics.map { |dl| bool_to_digit(dl.value) }.join
            end
          end

          def handle_s0003(_status_code, status_name = nil, _options = {})
            case status_name
            when 'inputstatus'
              TrafficControllerSite.make_status @inputs.actual_string
            when 'extendedinputstatus'
              TrafficControllerSite.make_status 0.to_s
            end
          end

          def handle_s0004(_status_code, status_name = nil, _options = {})
            case status_name
            when 'outputstatus', 'extendedoutputstatus'
              TrafficControllerSite.make_status 0
            end
          end

          def handle_s0005(_status_code, status_name = nil, _options = {})
            case status_name
            when 'status'
              TrafficControllerSite.make_status @is_starting
            when 'statusByIntersection'
              status = [
                {
                  'intersection' => '1',
                  'startup' => TrafficControllerSite.to_rmsp_bool(@is_starting)
                }
              ]
              TrafficControllerSite.make_status status
            end
          end

          def handle_s0006(_status_code, status_name = nil, options = {})
            if Proxy.version_meets_requirement? options[:sxl_version], '>=1.2.0'
              log 'S0006 is depreciated, use S0035 instead.',
                  level: :warning
            end
            status = @emergency_routes.any?
            case status_name
            when 'status'
              TrafficControllerSite.make_status status
            when 'emergencystage'
              TrafficControllerSite.make_status status ? @last_emergency_route : 0
            end
          end

          def handle_s0035(_status_code, status_name = nil, _options = {})
            case status_name
            when 'emergencyroutes'
              list = @emergency_routes.sort.map { |route| { 'id' => route.to_s } }
              TrafficControllerSite.make_status list
            end
          end
        end
      end
    end
  end
end
