# frozen_string_literal: true

module RSMP
  class Collector
    # Status predicate methods for collectors
    module Status
      # Is collection active?
      def collecting?
        @status == :collecting
      end

      # Is collection complete?
      def ok?
        @status == :ok
      end

      # Has collection timed out?
      def timeout?
        @status == :timeout
      end

      # Is collection ready to start?
      def ready?
        @status == :ready
      end

      # Has collection been cancelled?
      def cancelled?
        @status == :cancelled
      end

      # Want ingoing messages?
      def ingoing?
        @ingoing == true
      end

      # Want outgoing messages?
      def outgoing?
        @outgoing == true
      end
    end
  end
end
