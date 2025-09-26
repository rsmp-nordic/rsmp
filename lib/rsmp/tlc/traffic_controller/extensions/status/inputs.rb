module RSMP
  module TLC
    module TrafficControllerExtensions
      module Status
        module Inputs
          def handle_s0024(_status_code, status_name = nil, _options = {})
            case status_name
            when 'status'
              TrafficControllerSite.make_status '1-0'
            end
          end

          def handle_s0026(_status_code, status_name = nil, _options = {})
            case status_name
            when 'status'
              TrafficControllerSite.make_status '0-00'
            end
          end

          def handle_s0027(_status_code, status_name = nil, _options = {})
            case status_name
            when 'status'
              status = @day_time_table.map do |i, item|
                "#{i}-#{item[:plan]}-#{item[:hour]}-#{item[:min]}"
              end.join(',')
              TrafficControllerSite.make_status status
            end
          end

          def handle_s0028(_status_code, status_name = nil, _options = {})
            case status_name
            when 'status'
              times = @plans.map do |_nr, plan|
                "#{format('%02d', plan.number)}-#{format('%02d', plan.cycle_time)}"
              end.join(',')
              TrafficControllerSite.make_status times
            end
          rescue StandardError => e
            puts e
          end

          def handle_s0029(_status_code, status_name = nil, _options = {})
            case status_name
            when 'status'
              TrafficControllerSite.make_status @inputs.forced_string
            end
          end

          def handle_s0030(_status_code, status_name = nil, _options = {})
            case status_name
            when 'status'
              TrafficControllerSite.make_status ''
            end
          end

          def handle_s0031(_status_code, status_name = nil, _options = {})
            case status_name
            when 'status'
              TrafficControllerSite.make_status ''
            end
          end

          def handle_s0032(_status_code, status_name = nil, _options = {})
            case status_name
            when 'intersection'
              TrafficControllerSite.make_status @intersection
            when 'status'
              TrafficControllerSite.make_status 'local'
            when 'source'
              TrafficControllerSite.make_status @intersection_source
            end
          end

          def handle_s0033(_status_code, status_name = nil, _options = {})
            case status_name
            when 'status'
              TrafficControllerSite.make_status priority_list
            end
          end
        end
      end
    end
  end
end
