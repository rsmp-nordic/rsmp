module RSMP
  module TLC
    module TrafficControllerExtensions
      module Commands
        module ModeControl
          def handle_m0001(arg, _options = {})
            @node.verify_security_code 2, arg['securityCode']

            timeout = normalize_timeout(arg['timeout'].to_i)

            switch_functional_position arg['status'],
                                       timeout: timeout,
                                       source: 'forced'
          end

          def handle_m0007(arg, _options = {})
            @node.verify_security_code 2, arg['securityCode']
            set_fixed_time_control arg['status'], source: 'forced'
          end

          def set_fixed_time_control(status, source:)
            @fixed_time_control = status
            @fixed_time_control_source = source
          end

          def switch_functional_position(mode, source:, timeout: nil, reverting: false)
            unless %w[NormalControl YellowFlash Dark].include? mode
              raise RSMP::MessageRejected,
                    "Invalid functional position #{mode.inspect}, must be NormalControl, YellowFlash or Dark"
            end

            if reverting
              log "Reverting to functional position #{mode} after timeout", level: :info
            elsif timeout&.positive?
              log "Switching to functional position #{mode} with timeout #{(timeout / 60).round(1)}min", level: :info
              @previous_functional_position = @function_position
              now = clock.now
              @functional_position_timeout = now + timeout
            else
              log "Switching to functional position #{mode}", level: :info
            end
            initiate_startup_sequence if (mode == 'NormalControl') && (@function_position != 'NormalControl')
            @function_position = mode
            @function_position_source = source
            mode
          end

          private

          def normalize_timeout(timeout)
            return 1 if timeout == 1
            return timeout * 60 unless timeout.zero?

            0
          end
        end
      end
    end
  end
end
