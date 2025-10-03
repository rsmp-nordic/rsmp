# frozen_string_literal: true

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

        def string_to_bool(bool_str)
          case bool_str
          when 'True'
            true
          when 'False'
            false
          else
            raise RSMP::MessageRejected, "Invalid boolean '#{bool}', must be 'True' or 'False'"
          end
        end

        def bool_string_to_digit(bool)
          case bool
          when 'True'
            '1'
          when 'False'
            '0'
          else
            raise RSMP::MessageRejected, "Invalid boolean '#{bool}', must be 'True' or 'False'"
          end
        end

        def bool_to_digit(bool)
          bool ? '1' : '0'
        end
      end
    end
  end
end
