module RSMP
  module TLC
    module TrafficControllerExtensions
      module Commands
        module PlanManagement
          def handle_m0002(arg, _options = {})
            @node.verify_security_code 2, arg['securityCode']
            if TrafficControllerSite.from_rsmp_bool?(arg['status'])
              switch_plan arg['timeplan'], source: 'forced'
            else
              switch_plan 0, source: 'startup'
            end
          end

          def handle_m0003(arg, _options = {})
            @node.verify_security_code 2, arg['securityCode']
            switch_traffic_situation arg['traficsituation'], source: 'forced'
          end

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

          def switch_traffic_situation(situation, source: 'forced')
            @traffic_situation = situation.to_i
            @traffic_situation_source = source
          end

          private

          def find_plan(plan_nr)
            plan = @plans[plan_nr.to_i]
            raise InvalidMessage, "unknown signal plan #{plan_nr}, known only [#{@plans.keys.join(', ')}]" unless plan

            plan
          end
        end
      end
    end
  end
end
