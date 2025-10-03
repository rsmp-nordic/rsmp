# frozen_string_literal: true

module RSMP
  class Collector
    # Progress reporting and description methods for collectors
    module Reporting
      # return a string describing the types of messages we're collecting
      def describe_types
        [@filter&.type].flatten.join('/')
      end

      # return a string that describes whe number of messages, and type of message we're collecting
      def describe_num_and_type
        if @num && @num > 1
          "#{@num} #{describe_types}s"
        else
          describe_types
        end
      end

      # return a string that describes the attributes that we're looking for
      def describe_matcher
        h = { component: @filter&.component }.compact
        if h.empty?
          describe_num_and_type
        else
          "#{describe_num_and_type} #{h}"
        end
      end

      # Build a string describing how how progress reached before timeout
      def describe_progress
        str = "#{@title.capitalize} #{identifier} "
        str << "in response to #{@m_id} " if @m_id
        str << "timed out after #{@timeout}s, "
        str << "reaching #{@messages.size}/#{@num}"
        str
      end

      # get a short id in hex format, identifying ourself
      def identifier
        "Collect #{object_id.to_s(16)}"
      end
    end
  end
end
