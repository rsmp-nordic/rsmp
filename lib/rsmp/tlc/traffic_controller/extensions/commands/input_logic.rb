module RSMP
  module TLC
    module TrafficControllerExtensions
      module Commands
        module InputLogic
          def input_logic(input, change)
            return unless @input_programming && !change.nil?

            action = @input_programming[input]
            return unless action
            return unless action['raise_alarm']

            component = if action['component']
                          node.find_component action['component']
                        else
                          node.main
                        end
            alarm_code = action['raise_alarm']
            if change
              log "Activating input #{input} is programmed to raise alarm #{alarm_code} on #{component.c_id}",
                  level: :info
              component.activate_alarm alarm_code
            else
              log "Deactivating input #{input} is programmed to clear alarm #{alarm_code} on #{component.c_id}",
                  level: :info
              component.deactivate_alarm alarm_code
            end
          end
        end
      end
    end
  end
end
