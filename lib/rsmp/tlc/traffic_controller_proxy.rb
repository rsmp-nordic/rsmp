# Proxy for handling communication with a remote Traffic Light Controller (TLC).
# Provides high-level methods for interacting with TLC functionality.
# Acts as a mirror of the remote TLC by automatically subscribing to status updates.

module RSMP
  module TLC
    # Proxy for handling communication with a remote traffic light controller.
    class TrafficControllerProxy < SiteProxy
      attr_reader :timeplan_source, :timeplan, :timeouts,
                  :functional_position, :yellow_flash, :traffic_situation

      # Backwards-compatible accessors expected by tests and callers
      def current_plan
        @timeplan
      end

      def plan_source
        @timeplan_source
      end

      def initialize(options)
        super
        @timeplan_source = nil
        @timeplan = nil
        @functional_position = nil
        @yellow_flash = nil
        @traffic_situation = nil
        @timeouts = node.supervisor_settings.dig('default', 'timeouts') || {}
      end

      def handshake_complete
        super
        auto_subscribe_to_statuses
      end

      def subscribe_to_timeplan(options: {})
        validate_ready 'subscribe to timeplan'

        status_list = [{
          'sCI' => 'S0014',
          'n' => 'status',
          'sOc' => true
        }, {
          'sCI' => 'S0014',
          'n' => 'source',
          'sOc' => true
        }]

        merged_options = @timeouts.merge(options)

        raise 'TLC main component not found' unless main

        subscribe_to_status main.c_id, status_list, merged_options
      end

      # Override status update processing to automatically store cached status values.
      def process_status_update(message)
        super

        status_values = message.attribute('sS')
        return unless status_values

        status_values.each do |item|
          case item['sCI']
          when 'S0007'
            @functional_position = item['s'] if item['n'] == 'status'
          when 'S0011'
            @yellow_flash = item['s'] if item['n'] == 'status'
          when 'S0014'
            case item['n']
            when 'status'
              @timeplan = item['s'].to_i
            when 'source'
              @timeplan_source = item['s']
            end
          when 'S0015'
            @traffic_situation = item['s'] if item['n'] == 'status'
          end
        end
      end

      # Get all timeplan attributes stored in the main ComponentProxy.
      def timeplan_attributes
        main&.statuses&.dig('S0014') || {}
      end

      # Set the timeplan (signal plan) on the remote TLC
      def set_timeplan(plan_nr, options: {})
        validate_ready 'set timeplan'
        raise 'TLC main component not found' unless main

        security_code = security_code_for(2)

        command_list = [{
          'cCI' => 'M0002',
          'cO' => 'setPlan',
          'n' => 'status',
          'v' => 'True'
        }, {
          'cCI' => 'M0002',
          'cO' => 'setPlan',
          'n' => 'securityCode',
          'v' => security_code.to_s
        }, {
          'cCI' => 'M0002',
          'cO' => 'setPlan',
          'n' => 'timeplan',
          'v' => plan_nr.to_s
        }]

        confirm_status = [{ 'sCI' => 'S0014', 'n' => 'status', 's' => plan_nr.to_s }]
        send_command_with_confirm main.c_id, command_list, options, "timeplan #{plan_nr}", confirm_status
      end

      # M0001 — Set functional position (NormalControl, YellowFlash, Dark).
      def set_functional_position(status, timeout_minutes: 0, options: {})
        validate_ready 'set functional position'
        raise 'TLC main component not found' unless main

        security_code = security_code_for(2)

        command_list = [{
          'cCI' => 'M0001',
          'cO' => 'setValue',
          'n' => 'status',
          'v' => status.to_s
        }, {
          'cCI' => 'M0001',
          'cO' => 'setValue',
          'n' => 'securityCode',
          'v' => security_code.to_s
        }, {
          'cCI' => 'M0001',
          'cO' => 'setValue',
          'n' => 'timeout',
          'v' => timeout_minutes.to_s
        }, {
          'cCI' => 'M0001',
          'cO' => 'setValue',
          'n' => 'intersection',
          'v' => '0'
        }]

        confirm_status = functional_position_confirm_status(status)
        send_command_with_confirm main.c_id, command_list, options, "functional position #{status}", confirm_status
      end

      # M0003 — Set traffic situation (activate a specific situation number).
      def set_traffic_situation(situation, options: {})
        validate_ready 'set traffic situation'
        raise 'TLC main component not found' unless main

        security_code = security_code_for(2)

        command_list = [{
          'cCI' => 'M0003',
          'cO' => 'setTrafficSituation',
          'n' => 'status',
          'v' => 'True'
        }, {
          'cCI' => 'M0003',
          'cO' => 'setTrafficSituation',
          'n' => 'securityCode',
          'v' => security_code.to_s
        }, {
          'cCI' => 'M0003',
          'cO' => 'setTrafficSituation',
          'n' => 'traficsituation',
          'v' => situation.to_s
        }]

        confirm_status = [{ 'sCI' => 'S0015', 'n' => 'status', 's' => situation.to_s }]
        send_command_with_confirm main.c_id, command_list, options, "traffic situation #{situation}", confirm_status
      end
      def unset_traffic_situation(options: {})
        validate_ready 'unset traffic situation'
        raise 'TLC main component not found' unless main

        security_code = security_code_for(2)

        command_list = [{
          'cCI' => 'M0003',
          'cO' => 'setTrafficSituation',
          'n' => 'status',
          'v' => 'False'
        }, {
          'cCI' => 'M0003',
          'cO' => 'setTrafficSituation',
          'n' => 'securityCode',
          'v' => security_code.to_s
        }, {
          'cCI' => 'M0003',
          'cO' => 'setTrafficSituation',
          'n' => 'traficsituation',
          'v' => '1'
        }]

        confirm_status = [{ 'sCI' => 'S0015', 'n' => 'status', 's' => '1' }]
        send_command_with_confirm main.c_id, command_list, options, 'traffic situation unset', confirm_status
      end

      # M0005 — Set or clear an emergency route.
      def set_emergency_route(route:, active:, options: {})
        validate_ready 'set emergency route'
        raise 'TLC main component not found' unless main

        security_code = security_code_for(2)
        active_str = active ? 'True' : 'False'

        command_list = [{
          'cCI' => 'M0005',
          'cO' => 'setEmergency',
          'n' => 'status',
          'v' => active_str
        }, {
          'cCI' => 'M0005',
          'cO' => 'setEmergency',
          'n' => 'securityCode',
          'v' => security_code.to_s
        }, {
          'cCI' => 'M0005',
          'cO' => 'setEmergency',
          'n' => 'emergencyroute',
          'v' => route.to_s
        }]

        active_status = active ? 'True' : 'False'
        confirm_status = [{ 'sCI' => 'S0006', 'n' => 'status', 's' => active_status }]
        send_command_with_confirm main.c_id, command_list, options, "emergency route #{route} #{active ? 'active' : 'inactive'}", confirm_status
      end

      # M0006 — Set a single input to a given status.
      def set_input(input:, status:, options: {})
        validate_ready 'set input'
        raise 'TLC main component not found' unless main

        security_code = security_code_for(2)

        command_list = [{
          'cCI' => 'M0006',
          'cO' => 'setInput',
          'n' => 'status',
          'v' => status.to_s
        }, {
          'cCI' => 'M0006',
          'cO' => 'setInput',
          'n' => 'securityCode',
          'v' => security_code.to_s
        }, {
          'cCI' => 'M0006',
          'cO' => 'setInput',
          'n' => 'input',
          'v' => input.to_s
        }]

        send_command_with_confirm main.c_id, command_list, options, "input #{input} set to #{status}", nil
      end

      # M0007 — Enable or disable fixed-time control.
      def set_fixed_time(status, options: {})
        validate_ready 'set fixed time'
        raise 'TLC main component not found' unless main

        security_code = security_code_for(2)

        command_list = [{
          'cCI' => 'M0007',
          'cO' => 'setFixedTime',
          'n' => 'status',
          'v' => status.to_s
        }, {
          'cCI' => 'M0007',
          'cO' => 'setFixedTime',
          'n' => 'securityCode',
          'v' => security_code.to_s
        }]

        confirm_status = [{ 'sCI' => 'S0009', 'n' => 'status', 's' => /^#{Regexp.escape(status.to_s)}(,#{Regexp.escape(status.to_s)})*$/ }]
        send_command_with_confirm main.c_id, command_list, options, "fixed time #{status}", confirm_status
      end

      # M0008 — Force detector logic to a given mode and status.
      # component_id must refer to the detector logic component, not main.
      def force_detector_logic(component_id, status:, mode:, options: {})
        validate_ready 'force detector logic'

        security_code = security_code_for(2)

        command_list = [{
          'cCI' => 'M0008',
          'cO' => 'setForceDetectorLogic',
          'n' => 'status',
          'v' => status.to_s
        }, {
          'cCI' => 'M0008',
          'cO' => 'setForceDetectorLogic',
          'n' => 'securityCode',
          'v' => security_code.to_s
        }, {
          'cCI' => 'M0008',
          'cO' => 'setForceDetectorLogic',
          'n' => 'mode',
          'v' => mode.to_s
        }]

        send_command_with_confirm component_id, command_list, options, "force detector logic #{component_id}", nil
      end

      # M0010 — Order signal start for a signal group component.
      def order_signal_start(component_id, options: {})
        validate_ready 'order signal start'

        security_code = security_code_for(2)

        command_list = [{
          'cCI' => 'M0010',
          'cO' => 'setStart',
          'n' => 'status',
          'v' => 'True'
        }, {
          'cCI' => 'M0010',
          'cO' => 'setStart',
          'n' => 'securityCode',
          'v' => security_code.to_s
        }]

        send_command_with_confirm component_id, command_list, options, "signal start #{component_id}", nil
      end

      # M0011 — Order signal stop for a signal group component.
      def order_signal_stop(component_id, options: {})
        validate_ready 'order signal stop'

        security_code = security_code_for(2)

        command_list = [{
          'cCI' => 'M0011',
          'cO' => 'setStop',
          'n' => 'status',
          'v' => 'True'
        }, {
          'cCI' => 'M0011',
          'cO' => 'setStop',
          'n' => 'securityCode',
          'v' => security_code.to_s
        }]

        send_command_with_confirm component_id, command_list, options, "signal stop #{component_id}", nil
      end

      # M0013 — Set all inputs via a bit-pattern string.
      def set_inputs(status, options: {})
        validate_ready 'set inputs'
        raise 'TLC main component not found' unless main

        security_code = security_code_for(2)

        command_list = [{
          'cCI' => 'M0013',
          'cO' => 'setInputs',
          'n' => 'status',
          'v' => status.to_s
        }, {
          'cCI' => 'M0013',
          'cO' => 'setInputs',
          'n' => 'securityCode',
          'v' => security_code.to_s
        }]

        send_command_with_confirm main.c_id, command_list, options, "inputs #{status}", nil
      end

      # M0014 — Set dynamic bands for a signal plan.
      def set_dynamic_bands(plan:, status:, options: {})
        validate_ready 'set dynamic bands'
        raise 'TLC main component not found' unless main

        security_code = security_code_for(2)

        command_list = [{
          'cCI' => 'M0014',
          'cO' => 'setCommands',
          'n' => 'status',
          'v' => status.to_s
        }, {
          'cCI' => 'M0014',
          'cO' => 'setCommands',
          'n' => 'securityCode',
          'v' => security_code.to_s
        }, {
          'cCI' => 'M0014',
          'cO' => 'setCommands',
          'n' => 'plan',
          'v' => plan.to_s
        }]

        send_command_with_confirm main.c_id, command_list, options, "dynamic bands plan #{plan}", nil
      end

      # M0015 — Set offset for a signal plan.
      def set_offset(plan:, offset:, options: {})
        validate_ready 'set offset'
        raise 'TLC main component not found' unless main

        security_code = security_code_for(2)

        command_list = [{
          'cCI' => 'M0015',
          'cO' => 'setOffset',
          'n' => 'status',
          'v' => offset.to_s
        }, {
          'cCI' => 'M0015',
          'cO' => 'setOffset',
          'n' => 'securityCode',
          'v' => security_code.to_s
        }, {
          'cCI' => 'M0015',
          'cO' => 'setOffset',
          'n' => 'plan',
          'v' => plan.to_s
        }]

        send_command_with_confirm main.c_id, command_list, options, "offset plan #{plan} to #{offset}", nil
      end

      # M0016 — Set week table (mapping week days to traffic situations).
      def set_week_table(status, options: {})
        validate_ready 'set week table'
        raise 'TLC main component not found' unless main

        security_code = security_code_for(2)

        command_list = [{
          'cCI' => 'M0016',
          'cO' => 'setWeekTable',
          'n' => 'status',
          'v' => status.to_s
        }, {
          'cCI' => 'M0016',
          'cO' => 'setWeekTable',
          'n' => 'securityCode',
          'v' => security_code.to_s
        }]

        send_command_with_confirm main.c_id, command_list, options, 'week table', nil
      end

      # M0017 — Set day table (mapping time periods to signal plans).
      def set_day_table(status, options: {})
        validate_ready 'set day table'
        raise 'TLC main component not found' unless main

        security_code = security_code_for(2)

        command_list = [{
          'cCI' => 'M0017',
          'cO' => 'setDayTable',
          'n' => 'status',
          'v' => status.to_s
        }, {
          'cCI' => 'M0017',
          'cO' => 'setDayTable',
          'n' => 'securityCode',
          'v' => security_code.to_s
        }]

        send_command_with_confirm main.c_id, command_list, options, 'day table', nil
      end

      # M0018 — Set cycle time for a signal plan.
      def set_cycle_time(plan:, cycle_time:, options: {})
        validate_ready 'set cycle time'
        raise 'TLC main component not found' unless main

        security_code = security_code_for(2)

        command_list = [{
          'cCI' => 'M0018',
          'cO' => 'setCycleTime',
          'n' => 'status',
          'v' => cycle_time.to_s
        }, {
          'cCI' => 'M0018',
          'cO' => 'setCycleTime',
          'n' => 'securityCode',
          'v' => security_code.to_s
        }, {
          'cCI' => 'M0018',
          'cO' => 'setCycleTime',
          'n' => 'plan',
          'v' => plan.to_s
        }]

        send_command_with_confirm main.c_id, command_list, options, "cycle time plan #{plan} to #{cycle_time}", nil
      end

      # M0019 — Force an input to a given value.
      def force_input(input:, status:, value:, options: {})
        validate_ready 'force input'
        raise 'TLC main component not found' unless main

        security_code = security_code_for(2)

        command_list = [{
          'cCI' => 'M0019',
          'cO' => 'setInput',
          'n' => 'status',
          'v' => status.to_s
        }, {
          'cCI' => 'M0019',
          'cO' => 'setInput',
          'n' => 'securityCode',
          'v' => security_code.to_s
        }, {
          'cCI' => 'M0019',
          'cO' => 'setInput',
          'n' => 'input',
          'v' => input.to_s
        }, {
          'cCI' => 'M0019',
          'cO' => 'setInput',
          'n' => 'inputValue',
          'v' => value.to_s
        }]

        confirm_status = [
          { 'sCI' => 'S0029', 'n' => 'status', 's' => /^.{#{input.to_i - 1}}#{status == 'True' ? '1' : '0'}/ },
          { 'sCI' => 'S0003', 'n' => 'inputstatus', 's' => /^.{#{input.to_i - 1}}#{value == 'True' ? '1' : '0'}/ }
        ]
        send_command_with_confirm main.c_id, command_list, options, "force input #{input}", confirm_status
      end

      # M0020 — Force an output to a given value.
      def force_output(output:, status:, value:, options: {})
        validate_ready 'force output'
        raise 'TLC main component not found' unless main

        security_code = security_code_for(2)

        command_list = [{
          'cCI' => 'M0020',
          'cO' => 'setOutput',
          'n' => 'status',
          'v' => status.to_s
        }, {
          'cCI' => 'M0020',
          'cO' => 'setOutput',
          'n' => 'securityCode',
          'v' => security_code.to_s
        }, {
          'cCI' => 'M0020',
          'cO' => 'setOutput',
          'n' => 'output',
          'v' => output.to_s
        }, {
          'cCI' => 'M0020',
          'cO' => 'setOutput',
          'n' => 'outputValue',
          'v' => value.to_s
        }]

        send_command_with_confirm main.c_id, command_list, options, "force output #{output}", nil
      end

      # M0021 — Set the trigger level for traffic counting.
      def set_trigger_level(status, options: {})
        validate_ready 'set trigger level'
        raise 'TLC main component not found' unless main

        security_code = security_code_for(2)

        command_list = [{
          'cCI' => 'M0021',
          'cO' => 'setLevel',
          'n' => 'status',
          'v' => status.to_s
        }, {
          'cCI' => 'M0021',
          'cO' => 'setLevel',
          'n' => 'securityCode',
          'v' => security_code.to_s
        }]

        send_command_with_confirm main.c_id, command_list, options, "trigger level #{status}", nil
      end

      # M0023 — Set timeout for dynamic bands.
      def set_dynamic_bands_timeout(status, options: {})
        validate_ready 'set dynamic bands timeout'
        raise 'TLC main component not found' unless main

        security_code = security_code_for(2)

        command_list = [{
          'cCI' => 'M0023',
          'cO' => 'setTimeout',
          'n' => 'status',
          'v' => status.to_s
        }, {
          'cCI' => 'M0023',
          'cO' => 'setTimeout',
          'n' => 'securityCode',
          'v' => security_code.to_s
        }]

        send_command_with_confirm main.c_id, command_list, options, "dynamic bands timeout #{status}", nil
      end

      # M0103 — Change security code for a given level.
      # Does not use security_code_for since the codes are passed explicitly.
      def set_security_code(level:, old_code:, new_code:, options: {})
        validate_ready 'set security code'
        raise 'TLC main component not found' unless main

        command_list = [{
          'cCI' => 'M0103',
          'cO' => 'setSecurityCode',
          'n' => 'status',
          'v' => level.to_s
        }, {
          'cCI' => 'M0103',
          'cO' => 'setSecurityCode',
          'n' => 'oldSecurityCode',
          'v' => old_code.to_s
        }, {
          'cCI' => 'M0103',
          'cO' => 'setSecurityCode',
          'n' => 'newSecurityCode',
          'v' => new_code.to_s
        }]

        send_command_with_confirm main.c_id, command_list, options, "security code level #{level}", nil
      end

      # M0104 — Set the clock on the remote TLC. clock must respond to iso8601.
      def set_clock(clock, options: {})
        validate_ready 'set clock'
        raise 'TLC main component not found' unless main

        security_code = security_code_for(1)

        command_list = [{
          'cCI' => 'M0104',
          'cO' => 'setDate',
          'n' => 'securityCode',
          'v' => security_code.to_s
        }, {
          'cCI' => 'M0104',
          'cO' => 'setDate',
          'n' => 'year',
          'v' => clock.year.to_s
        }, {
          'cCI' => 'M0104',
          'cO' => 'setDate',
          'n' => 'month',
          'v' => clock.month.to_s
        }, {
          'cCI' => 'M0104',
          'cO' => 'setDate',
          'n' => 'day',
          'v' => clock.day.to_s
        }, {
          'cCI' => 'M0104',
          'cO' => 'setDate',
          'n' => 'hour',
          'v' => clock.hour.to_s
        }, {
          'cCI' => 'M0104',
          'cO' => 'setDate',
          'n' => 'minute',
          'v' => clock.min.to_s
        }, {
          'cCI' => 'M0104',
          'cO' => 'setDate',
          'n' => 'second',
          'v' => clock.sec.to_s
        }]

        send_command_with_confirm main.c_id, command_list, options, 'clock', nil
      end

      # Fetch the current signal plan from the remote TLC.
      def fetch_signal_plan(options: {})
        validate_ready 'fetch signal plan'

        status_list = [{
          'sCI' => 'S0014',
          'n' => 'status'
        }, {
          'sCI' => 'S0014',
          'n' => 'source'
        }]

        request_status main.c_id, status_list, @timeouts.merge(options)
      end

      # Subscribe to one or more statuses and wait until they match the expected values.
      # Raises RSMP::TimeoutError if the values don't match within the timeout.
      #
      # status_list items: { 'sCI' => ..., 'n' => ..., 's' => <expected value or Regexp> }
      # component_id defaults to the main TLC component.
      # timeout defaults to @timeouts['command'].
      def wait_for_status(description, status_list, update_rate: 0, timeout: nil, component_id: nil)
        validate_ready 'wait for status'
        component_id ||= main.c_id
        timeout ||= @timeouts['command']

        subscribe_list = status_list.map do |item|
          entry = item.merge('uRt' => update_rate.to_s)
          entry = entry.merge('sOc' => true) if use_soc?
          entry
        end

        log "Wait for #{description}", level: :debug

        begin
          subscribe_to_status component_id, subscribe_list, collect!: { timeout: timeout }
        ensure
          unsubscribe_list = status_list.map { |item| item.slice('sCI', 'n') }
          unsubscribe_to_status component_id, unsubscribe_list
        end
      end

      # Wait for all signal groups to match state (as regex string, e.g. 'c' for yellow flash).
      def wait_for_groups(state, timeout:)
        regex = /^#{state}+$/
        wait_for_status(
          "all groups to reach state #{state}",
          [{ 'sCI' => 'S0001', 'n' => 'signalgroupstatus', 's' => regex }],
          timeout: timeout
        )
      end

      # Wait for the TLC to return to normal control mode (functional position NormalControl,
      # yellow flash off, startup mode off).
      def wait_for_normal_control(timeout: nil)
        wait_for_status(
          'normal control on, yellow flash off, startup mode off',
          [
            { 'sCI' => 'S0007', 'n' => 'status', 's' => /^True(,True)*$/ },
            { 'sCI' => 'S0011', 'n' => 'status', 's' => /^False(,False)*$/ },
            { 'sCI' => 'S0005', 'n' => 'status', 's' => 'False' }
          ],
          timeout: timeout
        )
      end

      # Read cycle times for all plans via S0028.
      # Returns a hash of plan_nr (Integer) => cycle_time (Integer, seconds).
      def read_cycle_times(options: {})
        validate_ready 'read cycle times'
        timeout = options[:timeout] || @timeouts['status_response']
        result = request_status main.c_id,
                                [{ 'sCI' => 'S0028', 'n' => 'status' }],
                                collect!: { timeout: timeout }
        result[:collector].messages.first.attributes['sS'].first['s'].split(',').to_h do |item|
          item.split('-').map(&:to_i)
        end
      end

      # Read the current signal plan number via S0014.
      # Returns the plan number as an Integer.
      def read_current_plan(options: {})
        validate_ready 'read current plan'
        timeout = options[:timeout] || @timeouts['status_response']
        result = request_status main.c_id,
                                [{ 'sCI' => 'S0014', 'n' => 'status' }],
                                collect!: { timeout: timeout }
        result[:collector].messages.first.attributes['sS'].first['s'].to_i
      end

      # Read the value of a single dynamic band for a given plan and band index via S0023.
      # Returns the band value as an Integer, or nil if not found.
      def read_dynamic_band(plan:, band:, options: {})
        validate_ready 'read dynamic band'
        timeout = options[:timeout] || @timeouts['status_response']
        result = request_status main.c_id,
                                [{ 'sCI' => 'S0023', 'n' => 'status' }],
                                collect!: { timeout: timeout }
        result[:collector].messages.first.attributes['sS'].first['s'].split(',').each do |item|
          some_plan, some_band, value = item.split('-')
          return value.to_i if some_plan.to_i == plan.to_i && some_band.to_i == band.to_i
        end
        nil
      end

      # Returns true if sOc (send on change) should be used.
      # sOc is supported in RSMP core version 3.1.5 and later.
      def use_soc?
        return false unless core_version

        RSMP::Proxy.version_meets_requirement?(core_version, '>=3.1.5')
      end

      private

      # Automatically subscribe to key TLC statuses to keep proxy in sync.
      def auto_subscribe_to_statuses
        return unless main

        subscribe_to_timeplan
        subscribe_to_key_statuses
      end

      # Subscribe to S0001, S0007, S0011, S0015 for automatic caching.
      def subscribe_to_key_statuses
        status_list = [
          { 'sCI' => 'S0001', 'n' => 'signalgroupstatus', 'sOc' => true },
          { 'sCI' => 'S0007', 'n' => 'status', 'sOc' => true },
          { 'sCI' => 'S0011', 'n' => 'status', 'sOc' => true },
          { 'sCI' => 'S0015', 'n' => 'status', 'sOc' => true }
        ]
        subscribe_to_status main.c_id, status_list, @timeouts
      end

      # Look up security code for a given level from site settings.
      # Expects @site_settings['security_codes'] = { 1 => 'code1', 2 => 'code2' }
      def security_code_for(level)
        codes = @site_settings&.dig('security_codes') || {}
        code = codes[level] || codes[level.to_s]
        raise ArgumentError, "Security code for level #{level} is not configured" unless code

        code
      end

      # Send a command and, if confirm: or confirm!: is present in options, wait for
      # confirming status updates afterwards.
      #
      # confirm_description - human-readable label used in log output
      # confirm_status_list  - status items to wait for (passed to wait_for_status)
      # component_id         - component to wait on (defaults to main)
      #
      # If options[:confirm] is set, timeout errors are silently swallowed.
      # If options[:confirm!] is set, timeout errors are raised.
      def send_command_with_confirm(component_id, command_list, options, confirm_description, confirm_status_list)
        result = send_command component_id, command_list, @timeouts.merge(options.reject { |k, _| %i[confirm confirm!].include?(k) })

        confirm_opts = options[:confirm] || options[:confirm!]
        return result unless confirm_opts
        return result if confirm_status_list.nil? || confirm_status_list.empty?

        timeout = confirm_opts.is_a?(Hash) ? confirm_opts[:timeout] : nil
        wait_kwargs = { timeout: timeout }.compact
        begin
          wait_for_status confirm_description, confirm_status_list, **wait_kwargs
        rescue RSMP::TimeoutError
          raise if options[:confirm!]
        end

        result
      end

      # Returns the status list used to confirm a set_functional_position command.
      def functional_position_confirm_status(status)
        case status.to_s
        when 'YellowFlash'
          [{ 'sCI' => 'S0011', 'n' => 'status', 's' => /^True(,True)*$/ }]
        when 'Dark'
          [{ 'sCI' => 'S0007', 'n' => 'status', 's' => /^False(,False)*$/ }]
        when 'NormalControl'
          [
            { 'sCI' => 'S0007', 'n' => 'status', 's' => /^True(,True)*$/ },
            { 'sCI' => 'S0011', 'n' => 'status', 's' => /^False(,False)*$/ },
            { 'sCI' => 'S0005', 'n' => 'status', 's' => 'False' }
          ]
        else
          []
        end
      end
    end
  end
end
