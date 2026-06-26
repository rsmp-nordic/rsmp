module RSMP
  module TLC
    module Modules
      # Utility helper methods
      module Helpers
        def find_plan(plan_nr)
          plan = @plans[plan_nr.to_i]
          raise InvalidMessage, "unknown signal plan #{plan_nr}, known only [#{@plans.keys.join(', ')}]" unless plan

          plan
        end

        def bool_to_digit(bool)
          bool ? '1' : '0'
        end
      end
    end
  end
end
