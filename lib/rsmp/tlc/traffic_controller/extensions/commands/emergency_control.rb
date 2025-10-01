module RSMP
  module TLC
    module TrafficControllerExtensions
      module Commands
        module EmergencyControl
          def handle_m0005(arg, _options = {})
            @node.verify_security_code 2, arg['securityCode']
            route = arg['emergencyroute'].to_i
            enable = (arg['status'] == 'True')
            @last_emergency_route = route

            if enable
              if @emergency_routes.add? route
                log "Enabling emergency route #{route}", level: :info
              else
                log "Emergency route #{route} already enabled", level: :info
              end
            elsif @emergency_routes.delete? route
              log "Disabling emergency route #{route}", level: :info
            else
              log "Emergency route #{route} already disabled", level: :info
            end
          end
        end
      end
    end
  end
end
