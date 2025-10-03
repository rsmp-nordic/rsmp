# frozen_string_literal: true

module RSMP
  module TLC
    # Manages startup sequence state machine for traffic controllers
    class StartupSequence
      attr_reader :sequence, :position, :initiated_at

      def initialize(sequence)
        @sequence = sequence || []
        @active = false
        @initiated_at = nil
        @position = nil
      end

      def start
        @active = true
        @initiated_at = nil
        @position = nil
      end

      def stop
        @active = false
        @initiated_at = nil
        @position = nil
      end

      def active?
        @active
      end

      def complete?
        return false unless @active
        return false if @position.nil?

        @position >= @sequence.size
      end

      def current_state
        return nil unless @active
        return nil if @position.nil?
        return nil if @position >= @sequence.size

        @sequence[@position]
      end

      def advance
        return unless @active

        if @initiated_at.nil?
          @initiated_at = Time.now.to_i + 1
          @position = 0
        else
          @position = Time.now.to_i - @initiated_at
        end

        stop if complete?
      end
    end
  end
end
