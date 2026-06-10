require 'forwardable'

module RSMP
  module SXL
    class SupervisorInterface < Interface
      extend Forwardable

      def_delegators :proxy,
                     :request_status,
                     :request_status_and_collect,
                     :subscribe_to_status,
                     :subscribe_to_status_and_collect,
                     :unsubscribe_to_status,
                     :send_command,
                     :send_command_and_collect

      def process_message(_message); end
    end
  end
end
