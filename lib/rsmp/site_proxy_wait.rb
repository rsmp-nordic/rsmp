# waiting for various types of messages and reponses from remote sites
module RSMP
  module SiteProxyWait

    # Class for matching incoming messaging against a list of wanted statuses,
    # and flagging when everything has been matched.
    class StatusMatcher
      attr_reader :result, :messages

      # Initialize with a list a wanted statuses
      def initialize want, options={}
        @want = want.clone
        @result = {}
        @messages = []
        @m_id = options[:m_id]
      end

      # Check for MessageNotAck
      # If the original request identified by @m_id is rejected, we abort
      def check_not_ack message
        if message.is_a?(MessageNotAck)
          if message.attribute('oMId') == @m_id
            # Set result to an exception, but don't raise it.
            # This will be returned by the async task and stored as the task result
            # When the parent task call wait() on the task, the exception
            # will be raised in the parent task, and caught by RSpec.
            # RSpec will then show the error and record the test as failed
            m_id_short = RSMP::Message.shorten_m_id @m_id, 8
            @result = RSMP::MessageRejected.new("Status request #{m_id_short} was rejected: #{message.attribute('rea')}")
            @messages = [message]
            return true
          end
          return false
        end
      end

      # Check if a messages is wanted.
      # Returns true when we found all that we want.
      def process message
        ack_status = check_not_ack message
        return ack_status if ack_status != nil

        add = false
        @want.each_with_index do |query,i|          # look through wanted
          message.attributes['sS'].each do |input|  # look through status items in message
            matching = status_match? query, input
            if matching == true
              @result[query] = input
              add = true
            elsif matching == false
              @result.delete query
            end
          end
        end
        @messages << message if add
        @result.size == @want.size      # queries left to match?
      end

      # Match an item against a query
      def status_match? query, item
        return nil if query['sCI'] && query['sCI'] != item['sCI']
        return nil if query['n'] && query['n'] != item['n']
        return false if query['q'] && query['q'] != item['q']
        if query['s'].is_a? Regexp
          return false if query['s'] && item['s'] !~ query['s']
        else
          return false if query['s'] && item['s'] != query['s']
        end
        true
      end
    end


    def wait_for_alarm parent_task, options={}
      matching_alarm = nil
      message = collect(parent_task,options.merge(type: "Alarm", with_message: true, num: 1)) do |message|
        # TODO check components
        matching_alarm = nil
        alarm = message
        next if options[:aCId] && options[:aCId] != alarm.attribute("aCId")
        next if options[:aSp] && options[:aSp] != alarm.attribute("aSp")
        next if options[:aS] && options[:aS] != alarm.attribute("aS")
        matching_alarm = alarm
        break
      end
      if item
        { message: message, status: matching_alarm }
      end
    end

    def collect_status_updates task, options, m_id
      collect_status_updates_or_responses task, 'StatusUpdate', options, m_id
    end

    def collect_status_responses task, options, m_id
      collect_status_updates_or_responses task, 'StatusResponse', options, m_id
    end

    def collect_command_responses parent_task, options, m_id
      task.annotate "wait for command response"
      want = options[:command_list].clone
      result = {}
      messages = []
      collect(parent_task,options.merge({
        type: ['CommandResponse','MessageNotAck'],
        num: 1
      })) do |message|
        if message.is_a?(MessageNotAck)
          if message.attribute('oMId') == m_id
            # set result to an exception, but don't raise it.
            # this will be returned by the task and stored as the task result
            # when the parent task call wait() on the task, the exception
            # will be raised in the parent task, and caught by rspec.
            # rspec will then show the error and record the test as failed
            m_id_short = RSMP::Message.shorten_m_id m_id, 8
            result = RSMP::MessageRejected.new "Command request #{m_id_short} was rejected: #{message.attribute('rea')}"
            next true   # done, no more messages wanted
          else
            false
          end
        else
          add = false
          # look through querues
          want.each_with_index do |query,i|
            # look through items in message
            message.attributes['rvs'].each do |input|
              matching = command_match? query, input
              if matching == true
                result[query] = input
                add = true
              elsif matching == false
                result.delete query
              end
            end
          end
          messages << message if add
          result.size == want.size # any queries left to match?
        end
      end
      return result, messages
    rescue Async::TimeoutError
      raise RSMP::TimeoutError.new "Did not receive correct command response to #{m_id} within #{options[:timeout]}s"
    end

    def collect_status_updates_or_responses task, type, options, m_id
      matcher = StatusMatcher.new options[:status_list], m_id: m_id
      rejected = nil
      collect(task,options.merge( type: [type,'MessageNotAck'], num: 1 )) do |message|
        matcher.process message   # returns true when done (all queries matched)
      end
      return matcher.result, matcher.messages
    rescue Async::TimeoutError
      type_str = {'StatusUpdate'=>'update', 'StatusResponse'=>'response'}[type]
      raise RSMP::TimeoutError.new "Did not received correct status #{type_str} in reply to #{m_id} within #{options[:timeout]}s"
    end

    def command_match? query, item
      return nil if query['cCI'] && query['cCI'] != item['cCI']
      return nil if query['n'] && query['n'] != item['n']
      if query['v'].is_a? Regexp
        return false if query['v'] && item['v'] !~ query['v']
      else
        return false if query['v'] && item['v'] != query['v']
      end
      true
    end

    def wait_for_aggregated_status parent_task, options, m_id
      collect(parent_task,options.merge({
        type: ['AggregatedStatus','MessageNotAck'],
        num: 1
      })) do |message|
        if message.is_a?(MessageNotAck)
          if message.attribute('oMId') == m_id
            # set result to an exception, but don't raise it.
            # this will be returned by the task and stored as the task result
            # when the parent task call wait() on the task, the exception
            # will be raised in the parent task, and caught by rspec.
            # rspec will then show the error and record the test as failed
            m_id_short = RSMP::Message.shorten_m_id m_id, 8
            result = RSMP::MessageRejected.new "Aggregated status request #{m_id_short} was rejected: #{message.attribute('rea')}"
            next true   # done, no more messages wanted
          else
            false
          end
        else
          true
        end
      end
    end

  end
end
