module RSMP
  module TLC
    module Proxy
      # Status reading and waiting methods for a remote TLC.
      # Covers status subscriptions, group waits, and plan/band reading.
      module Status
        # Fetch the current signal plan from the remote TLC.
        def fetch_signal_plan(options: {})
          validate_ready 'fetch signal plan'
          timeout = options[:timeout] || @timeouts['status_response']
          result = request_status({ S0014: %i[status source] }, within: timeout)
          result[:collector].messages.last.attributes['sS'].each_with_object({}) do |item, hash|
            hash[item['n']] = item['s']
          end
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
            subscribe_to_status subscribe_list, component: component_id, within: timeout
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
          result = request_status({ S0028: [:status] }, within: timeout)
          result[:collector].messages.first.attributes['sS'].first['s'].split(',').to_h do |item|
            item.split('-').map(&:to_i)
          end
        end

        # Read the current signal plan number via S0014.
        # Returns the plan number as an Integer.
        def read_current_plan(options: {})
          validate_ready 'read current plan'
          timeout = options[:timeout] || @timeouts['status_response']
          result = request_status({ S0014: [:status] }, within: timeout)
          result[:collector].messages.first.attributes['sS'].first['s'].to_i
        end

        # Read the value of a single dynamic band for a given plan and band index via S0023.
        # Returns the band value as an Integer, or nil if not found.
        def read_dynamic_band(plan:, band:, options: {})
          validate_ready 'read dynamic band'
          timeout = options[:timeout] || @timeouts['status_response']
          result = request_status({ S0023: [:status] }, within: timeout)
          extract_band_value(result, plan, band)
        end

        private

        def extract_band_value(result, plan, band)
          result[:collector].messages.first.attributes['sS'].first['s'].split(',').each do |item|
            some_plan, some_band, value = item.split('-')
            return value.to_i if some_plan.to_i == plan.to_i && some_band.to_i == band.to_i
          end
          nil
        end
      end
    end
  end
end
