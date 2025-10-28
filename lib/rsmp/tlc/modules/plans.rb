module RSMP
  module TLC
    module Modules
      # Time plans, traffic situations, and scheduling management
      # Handles time plan selection, dynamic bands, schedules, and cycle times
      module Plans
        def current_plan
          # TODO: plan 0 should means use time table
          return unless @plans

          @plans[plan] || @plans.values.first
        end

        # M0002 - Set current time plan
        def handle_m0002(arg, _options = {})
          @node.verify_security_code 2, arg['securityCode']
          if TrafficControllerSite.from_rsmp_bool?(arg['status'])
            switch_plan arg['timeplan'], source: 'forced'
          else
            switch_plan 0, source: 'startup' # TODO: use clock/calender
          end
        end

        # M0003 - Set traffic situation
        def handle_m0003(arg, _options = {})
          @node.verify_security_code 2, arg['securityCode']
          switch_traffic_situation arg['traficsituation']
        end

        def find_plan(plan_nr)
          plan = @plans[plan_nr.to_i]
          raise InvalidMessage, "unknown signal plan #{plan_nr}, known only [#{@plans.keys.join(', ')}]" unless plan

          plan
        end

        def switch_plan(plan, source:)
          plan_nr = plan.to_i
          if plan_nr.zero?
            log 'Switching to plan selection by time table', level: :info
          else
            find_plan plan_nr
            log "Switching to plan #{plan_nr}", level: :info
          end
          @plan = plan_nr
          @plan_source = source
        end

        def switch_traffic_situation(situation)
          @traffic_situation = situation.to_i
          @traffic_situation_source = 'forced'
        end

        # M0014 - Set dynamic bands
        def handle_m0014(arg, _options = {})
          @node.verify_security_code 2, arg['securityCode']
          plan = find_plan arg['plan']
          arg['status'].split(',').each do |item|
            matched = /(\d+)-(\d+)/.match item
            band = matched[1].to_i
            value = matched[2].to_i
            log "Set plan #{arg['plan']} dynamic band #{band} to #{value}", level: :info
            plan.set_band band, value
          end
        end

        # M0015 - Set offset time
        def handle_m0015(arg, _options = {})
          @node.verify_security_code 2, arg['securityCode']
        end

        # M0016 - Set week time table
        def handle_m0016(arg, _options = {})
          @node.verify_security_code 2, arg['securityCode']
        end

        # M0017 - Set time tables
        def handle_m0017(arg, _options = {})
          @node.verify_security_code 2, arg['securityCode']
          arg['status'].split(',').each do |item|
            elems = item.split('-')
            nr = elems[0].to_i
            plan = elems[1].to_i
            hour = elems[2].to_i
            min = elems[3].to_i
            raise InvalidMessage, "time table id must be between 0 and 12, got #{nr}" if nr.negative? || nr > 12

            @day_time_table[nr] = { plan: plan, hour: hour, min: min }
          end
        end

        # M0018 - Set cycle time
        def handle_m0018(arg, _options = {})
          @node.verify_security_code 2, arg['securityCode']
          nr = arg['plan'].to_i
          cycle_time = arg['status'].to_i
          plan = @plans[nr]
          raise RSMP::MessageRejected, "Plan '#{nr}' not found" unless plan
          raise RSMP::MessageRejected, 'Cycle time must be greater or equal to zero' if cycle_time.negative?

          log "Set plan #{nr} cycle time to #{cycle_time}", level: :info
          plan.cycle_time = cycle_time
        end

        # M0023 - Dynamic bands timeout
        def handle_m0023(arg, _options = {})
          @node.verify_security_code 2, arg['securityCode']
          timeout = arg['status'].to_i
          unless (timeout >= 0) && (timeout <= 65_535)
            raise RSMP::MessageRejected,
                  "Timeout must be in the range 0-65535, got #{timeout}"
          end

          if timeout.zero?
            log 'Dynamic bands timeout disabled', level: :info
          else
            log "Dynamic bands timeout set to #{timeout}min", level: :info
          end
          @dynamic_bands_timeout = timeout
        end

        # S0014 - Current signal program
        def handle_s0014(_status_code, status_name = nil, _options = {})
          case status_name
          when 'status'
            TrafficControllerSite.make_status @plan
          when 'source'
            TrafficControllerSite.make_status @plan_source
          end
        end

        # S0015 - Current traffic situation
        def handle_s0015(_status_code, status_name = nil, _options = {})
          case status_name
          when 'status'
            TrafficControllerSite.make_status @traffic_situation
          when 'source'
            TrafficControllerSite.make_status @traffic_situation_source
          end
        end

        # S0018 - Number of time plans
        def handle_s0018(_status_code, status_name = nil, _options = {})
          case status_name
          when 'number'
            TrafficControllerSite.make_status @plans.size
          end
        end

        # S0019 - Number of traffic situations
        def handle_s0019(_status_code, status_name = nil, _options = {})
          case status_name
          when 'number'
            TrafficControllerSite.make_status @num_traffic_situations
          end
        end

        # S0022 - List of time plans
        def handle_s0022(_status_code, status_name = nil, _options = {})
          case status_name
          when 'status'
            TrafficControllerSite.make_status @plans.keys.join(',')
          end
        end

        # S0023 - Dynamic bands
        def handle_s0023(_status_code, status_name = nil, _options = {})
          case status_name
          when 'status'
            dynamic_bands = @plans.map { |_nr, plan| plan.dynamic_bands_string }
            str = dynamic_bands.compact.join(',')
            TrafficControllerSite.make_status str
          end
        end

        # S0024 - Offset times
        def handle_s0024(_status_code, status_name = nil, _options = {})
          case status_name
          when 'status'
            TrafficControllerSite.make_status '1-0'
          end
        end

        # S0026 - Week time table
        def handle_s0026(_status_code, status_name = nil, _options = {})
          case status_name
          when 'status'
            TrafficControllerSite.make_status '0-00'
          end
        end

        # S0027 - Time tables
        def handle_s0027(_status_code, status_name = nil, _options = {})
          case status_name
          when 'status'
            status = @day_time_table.map do |i, item|
              "#{i}-#{item[:plan]}-#{item[:hour]}-#{item[:min]}"
            end.join(',')
            TrafficControllerSite.make_status status
          end
        end

        # S0028 - Cycle time
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
      end
    end
  end
end
