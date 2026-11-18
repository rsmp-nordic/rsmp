module RSMP
  class SiteProxy < Proxy
    module Modules
      # Opt-in Test Hub scenarios. Actions use the ordinary RSMP send/receive path.
      module TestHints
        def clear
          super
          @test_hint_subscription = nil
        end

        def process_not_ack(message)
          return super unless ready? && @site_settings['test_hints'] == true
          return super unless sxl_interfaces.key?('tlc') && main

          case TestHint.scenario(message)
          when 'M0002.set_plan'
            send_test_plan_command
          when 'S0014.subscribe_once'
            subscribe_to_test_plan
          else
            super
          end
        end

        def send_test_plan_command
          # Prototype fixture: plan 1 and code 2222 match the simulated site's config.
          send_command!(
            [
              { 'cCI' => 'M0002', 'cO' => 'setPlan', 'n' => 'status', 'v' => true },
              { 'cCI' => 'M0002', 'cO' => 'setPlan', 'n' => 'securityCode', 'v' => '2222' },
              { 'cCI' => 'M0002', 'cO' => 'setPlan', 'n' => 'timeplan', 'v' => 1 }
            ]
          )
        end

        def subscribe_to_test_plan
          @test_hint_subscription = main.c_id
          item = { 'sCI' => 'S0014', 'n' => 'status', 'uRt' => '1' }
          item['sOc'] = false if tlc.use_soc?
          subscribe_to_status!([item])
        end

        def process_status_update(message)
          super
          return unless @test_hint_subscription == message.attribute('cId')
          return unless message.attribute('sS').any? { |item| item['sCI'] == 'S0014' && item['n'] == 'status' }

          # The normal handler above acknowledges the update before we unsubscribe.
          component = @test_hint_subscription
          @test_hint_subscription = nil
          unsubscribe_to_status([{ 'sCI' => 'S0014', 'n' => 'status' }], component: component).value!
        end
      end
    end
  end
end
