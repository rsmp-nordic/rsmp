module RSMP
  module TLC
    module TrafficControllerExtensions
      module Status
        module System
          module User
            def handle_s0091(_status_code, status_name = nil, options = {})
              if Proxy.version_meets_requirement? options[:sxl_version], '>=1.1'
                case status_name
                when 'user'
                  TrafficControllerSite.make_status 0
                end
              else
                case status_name
                when 'user'
                  TrafficControllerSite.make_status 'nobody'
                when 'status'
                  TrafficControllerSite.make_status 'logout'
                end
              end
            end

            def handle_s0092(_status_code, status_name = nil, options = {})
              if Proxy.version_meets_requirement? options[:sxl_version], '>=1.1'
                case status_name
                when 'user'
                  TrafficControllerSite.make_status 0
                end
              else
                case status_name
                when 'user'
                  TrafficControllerSite.make_status 'nobody'
                when 'status'
                  TrafficControllerSite.make_status 'logout'
                end
              end
            end
          end
        end
      end
    end
  end
end
