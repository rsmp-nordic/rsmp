require 'forwardable'

module RSMP
  module SXL
    # Base interface for SXL-specific behavior on a proxy connection.
    class Interface
      extend Forwardable

      def_delegators :proxy, :send_message, :send_message_and_collect, :validate_ready, :log

      attr_reader :proxy, :name, :version

      def initialize(proxy:, name:, version:)
        @proxy = proxy
        @name = name
        @version = version
      end

      def node
        proxy.node
      end

      def components
        proxy.respond_to?(:components) ? proxy.components : proxy.site.components
      end

      def main
        proxy.respond_to?(:main) ? proxy.main : proxy.site.main
      end

      def sxl_version
        version
      end

      def core_version
        proxy.core_version
      end

      def use_soc?
        return false unless core_version

        RSMP::Proxy.version_meets_requirement?(core_version, '>=3.1.5')
      end

      def validate_message!(_message); end
    end
  end
end
