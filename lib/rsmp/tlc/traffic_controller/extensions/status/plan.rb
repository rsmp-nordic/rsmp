module RSMP
  module TLC
    module TrafficControllerExtensions
      module Status
        module Plan
          def handle_s0014(_status_code, status_name = nil, _options = {})
            case status_name
            when 'status'
              TrafficControllerSite.make_status @plan
            when 'source'
              TrafficControllerSite.make_status @plan_source
            end
          end

          def handle_s0015(_status_code, status_name = nil, _options = {})
            case status_name
            when 'status'
              TrafficControllerSite.make_status @traffic_situation
            when 'source'
              TrafficControllerSite.make_status @traffic_situation_source
            end
          end

          def handle_s0016(_status_code, status_name = nil, _options = {})
            case status_name
            when 'number'
              TrafficControllerSite.make_status @detector_logics.size
            end
          end

          def handle_s0017(_status_code, status_name = nil, _options = {})
            case status_name
            when 'number'
              TrafficControllerSite.make_status @signal_groups.size
            end
          end

          def handle_s0018(_status_code, status_name = nil, _options = {})
            case status_name
            when 'number'
              TrafficControllerSite.make_status @plans.size
            end
          end

          def handle_s0019(_status_code, status_name = nil, _options = {})
            case status_name
            when 'number'
              TrafficControllerSite.make_status @num_traffic_situations
            end
          end

          def handle_s0020(_status_code, status_name = nil, _options = {})
            case status_name
            when 'intersection'
              TrafficControllerSite.make_status @intersection
            when 'controlmode'
              TrafficControllerSite.make_status @control_mode
            end
          end

          def handle_s0021(_status_code, status_name = nil, _options = {})
            case status_name
            when 'detectorlogics'
              TrafficControllerSite.make_status @detector_logics.map { |logic| bool_to_digit(logic.forced) }.join
            end
          end

          def handle_s0022(_status_code, status_name = nil, _options = {})
            case status_name
            when 'status'
              TrafficControllerSite.make_status @plans.keys.join(',')
            end
          end

          def handle_s0023(_status_code, status_name = nil, _options = {})
            case status_name
            when 'status'
              dynamic_bands = @plans.map { |_nr, plan| plan.dynamic_bands_string }
              str = dynamic_bands.compact.join(',')
              TrafficControllerSite.make_status str
            end
          end
        end
      end
    end
  end
end
