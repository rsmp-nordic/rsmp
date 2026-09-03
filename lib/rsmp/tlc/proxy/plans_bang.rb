module RSMP
  module TLC
    module Proxy
      # Explicit exception-raising variants of finite plan operations.
      module PlansBang
        def set_dynamic_bands!(...)
          set_dynamic_bands(...).value!
        end

        def set_dynamic_bands_timeout!(...)
          set_dynamic_bands_timeout(...).value!
        end

        def set_offset!(...)
          set_offset(...).value!
        end

        def set_timeplan!(...)
          set_timeplan(...).value!
        end

        def set_week_table!(...)
          set_week_table(...).value!
        end

        def set_day_table!(...)
          set_day_table(...).value!
        end

        def set_cycle_time!(...)
          set_cycle_time(...).value!
        end

        def order_signal_start!(...)
          order_signal_start(...).value!
        end

        def order_signal_stop!(...)
          order_signal_stop(...).value!
        end
      end
    end
  end
end
