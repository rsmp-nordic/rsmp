# frozen_string_literal: true

module RSMP
  module TLC
    module Modules
      # Signal groups, detector logics, and priority handling
      # Handles signal control commands and status queries
      module SignalGroups
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

            # p "nr: #{nr}, plan #{plan} at #{hour}:#{min}"
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

        # M0019 - Force input
        def handle_m0019(arg, _options = {})
          @node.verify_security_code 2, arg['securityCode']
          input = arg['input'].to_i
          force = string_to_bool arg['status']
          forced_value = string_to_bool arg['inputValue']
          raise MessageRejected, "Input must be in the range 1-#{@inputs.size}" unless input.between?(1, @inputs.size)

          if force
            log "Forcing input #{input} to #{forced_value}", level: :info
          else
            log "Releasing input #{input}", level: :info
          end
          change = @inputs.set_forcing input, force: force, forced_value: forced_value

          input_logic input, change unless change.nil?
        end

        # M0020 - Force output
        def handle_m0020(arg, _options = {})
          @node.verify_security_code 2, arg['securityCode']
        end

        # M0021 - Force detector logic
        def handle_m0021(arg, _options = {})
          @node.verify_security_code 2, arg['securityCode']
        end

        # M0022 - Signal priority request
        def handle_m0022(arg, _options = {})
          id = arg['requestId']
          type = arg['type']
          priority = @signal_priorities.find { |priority| priority.id == id }
          case type
          when 'new'
            raise MessageRejected, "Priority Request #{id} already exists" if priority

            # ref = arg.slice('signalGroupId','inputId','connectionId','approachId','laneInId','laneOutId')
            signal_group = node.find_component arg['signalGroupId'] if arg['signalGroupId']

            level = arg['level']
            eta = arg['eta']
            vehicle_type = arg['vehicleType']
            @signal_priorities << SignalPriority.new(node: self, id: id, level: level, eta: eta,
                                                     vehicle_type: vehicle_type)
            log "Priority request #{id} for signal group #{signal_group.c_id} received.", level: :info

          when 'update'
            raise MessageRejected, "Cannot update priority request #{id}, not found" unless priority

            log "Updating Priority Request #{id}", level: :info

          when 'cancel'
            raise MessageRejected, "Cannot cancel priority request #{id}, not found" unless priority

            priority.cancel
            log "Priority request with id #{id} cancelled.", level: :info

          else
            raise MessageRejected, "Unknown type #{type}"
          end
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

        # S0008 - Manual control status
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

        # S0009 - Fixed time control status
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

        # S0010 - Isolated control status
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

        # S0011 - Yellow flash status
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

        # S0012 - All red status
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

        # S0013 - Police key status
        def handle_s0013(_status_code, status_name = nil, _options = {})
          case status_name
          when 'intersection'
            TrafficControllerSite.make_status @intersection
          when 'status'
            TrafficControllerSite.make_status @police_key
          end
        end

        # S0095 - Version information
        def handle_s0095(_status_code, status_name = nil, _options = {})
          case status_name
          when 'status'
            TrafficControllerSite.make_status RSMP::VERSION
          end
        end

        # S0096 - Current date and time
        def handle_s0096(_status_code, status_name = nil, _options = {})
          now = clock.now
          case status_name
          when 'year'
            TrafficControllerSite.make_status now.year.to_s.rjust(4, '0')
          when 'month'
            TrafficControllerSite.make_status now.month.to_s.rjust(2, '0')
          when 'day'
            TrafficControllerSite.make_status now.day.to_s.rjust(2, '0')
          when 'hour'
            TrafficControllerSite.make_status now.hour.to_s.rjust(2, '0')
          when 'minute'
            TrafficControllerSite.make_status now.min.to_s.rjust(2, '0')
          when 'second'
            TrafficControllerSite.make_status now.sec.to_s.rjust(2, '0')
          end
        end

        # S0097 - Configuration checksum
        def handle_s0097(_status_code, status_name = nil, _options = {})
          case status_name
          when 'checksum'
            TrafficControllerSite.make_status '1'
          when 'timestamp'
            now = clock.to_s
            TrafficControllerSite.make_status now
          end
        end

        # S0098 - Configuration data
        def handle_s0098(_status_code, status_name = nil, _options = {})
          settings = node.site_settings.slice('components', 'signal_plans', 'inputs', 'startup_sequence')
          json = JSON.generate(settings)
          case status_name
          when 'config'
            TrafficControllerSite.make_status json
          when 'timestamp'
            now = clock.to_s
            TrafficControllerSite.make_status now
          when 'version'
            TrafficControllerSite.make_status Digest::MD5.hexdigest(json)
          end
        end
      end
    end
  end
end
