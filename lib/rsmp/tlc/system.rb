# frozen_string_literal: true

module RSMP
  module TLC
    # System-level commands and status for traffic controllers
    # Handles restart, emergency routes, security, and clock settings
    module System
      # M0004 - Restart traffic light controller
      def handle_m0004(arg, _options = {})
        @node.verify_security_code 2, arg['securityCode']
        # don't restart immeediately, since we need to first send command response
        # instead, defer an action, which will be handled by the TLC site
        log 'Sheduling restart of TLC', level: :info
        @node.defer :restart
      end

      # M0005 - Enable/disable emergency route
      def handle_m0005(arg, _options = {})
        @node.verify_security_code 2, arg['securityCode']
        route = arg['emergencyroute'].to_i
        enable = (arg['status'] == 'True')
        @last_emergency_route = route

        if enable
          if @emergency_routes.add? route
            log "Enabling emergency route #{route}", level: :info
          else
            log "Emergency route #{route} already enabled", level: :info
          end
        elsif @emergency_routes.delete? route
          log "Disabling emergency route #{route}", level: :info
        else
          log "Emergency route #{route} already disabled", level: :info
        end
      end

      # M0103 - Set security code
      def handle_m0103(arg, _options = {})
        level = { 'Level1' => 1, 'Level2' => 2 }[arg['status']]
        @node.change_security_code level, arg['oldSecurityCode'], arg['newSecurityCode']
      end

      # M0104 - Set clock
      def handle_m0104(arg, _options = {})
        @node.verify_security_code 1, arg['securityCode']
        time = Time.new(
          arg['year'],
          arg['month'],
          arg['day'],
          arg['hour'],
          arg['minute'],
          arg['second'],
          'UTC'
        )
        clock.set time
        log "Clock set to #{time}, (adjustment is #{clock.adjustment}s)", level: :info
      end
    end
  end
end
