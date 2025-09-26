module RSMP
  module TLC
    module TrafficControllerExtensions
      module Status
        module Control
          def handle_s0007(_status_code, status_name = nil, _options = {})
            case status_name
            when 'intersection'
              TrafficControllerSite.make_status @intersection
            when 'status'
              TrafficControllerSite.make_status @function_position != 'Dark'
            when 'source'
              TrafficControllerSite.make_status @function_position_source
            end
          end

          def handle_s0008(_status_code, status_name = nil, _options = {})
            case status_name
            when 'intersection'
              TrafficControllerSite.make_status @intersection
            when 'status'
              TrafficControllerSite.make_status @manual_control
            when 'source'
              TrafficControllerSite.make_status @manual_control_source
            end
          end

          def handle_s0009(_status_code, status_name = nil, _options = {})
            case status_name
            when 'intersection'
              TrafficControllerSite.make_status @intersection
            when 'status'
              TrafficControllerSite.make_status @fixed_time_control
            when 'source'
              TrafficControllerSite.make_status @fixed_time_control_source
            end
          end

          def handle_s0010(_status_code, status_name = nil, _options = {})
            case status_name
            when 'intersection'
              TrafficControllerSite.make_status @intersection
            when 'status'
              TrafficControllerSite.make_status @isolated_control
            when 'source'
              TrafficControllerSite.make_status @isolated_control_source
            end
          end

          def handle_s0011(_status_code, status_name = nil, _options = {})
            case status_name
            when 'intersection'
              TrafficControllerSite.make_status @intersection
            when 'status'
              TrafficControllerSite.make_status TrafficControllerSite.to_rmsp_bool(@function_position == 'YellowFlash')
            when 'source'
              TrafficControllerSite.make_status @function_position_source
            end
          end

          def handle_s0012(_status_code, status_name = nil, _options = {})
            case status_name
            when 'intersection'
              TrafficControllerSite.make_status @intersection
            when 'status'
              TrafficControllerSite.make_status @all_red
            when 'source'
              TrafficControllerSite.make_status @all_red_source
            end
          end

          def handle_s0013(_status_code, status_name = nil, _options = {})
            case status_name
            when 'intersection'
              TrafficControllerSite.make_status @intersection
            when 'status'
              TrafficControllerSite.make_status @police_key
            end
          end
        end
      end
    end
  end
end
