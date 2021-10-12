# waiting for various types of messages and reponses from remote sites
module RSMP
  module SiteProxyWait


    # Base class for matching incoming messages against a list of queries.
    # Queries are specified as an array of hashes, e.g
    # [
    #   {"cCI"=>"M0104", "cO"=>"setDate", "n"=>"securityCode", "v"=>"1111"},
    #   {"cCI"=>"M0104", "cO"=>"setDate", "n"=>"year", "v"=>"2020"},
    #   {"cCI"=>"M0104", "cO"=>"setDate", "n"=>"month", "v"=>/\d+/}
    #  ]
    #
    # Note that queries can contain regex patterns for values, like /\d+/ in the example above.
    #
    # When an input messages is received it typically contains several items, eg:
    # [
    #   {"cCI"=>"M0104", "n"=>"month", "v"=>"9", "age"=>"recent"},
    #   {"cCI"=>"M0104", "n"=>"day", "v"=>"29", "age"=>"recent"},
    #   {"cCI"=>"M0104", "n"=>"hour", "v"=>"17", "age"=>"recent"}
    # ]
    #
    # Each of the input items is matched against each of the queries.
    # If a match is found, it's stored in the @results hash, with the query as the key,
    # and a mesage and status as the key. In the example above, this query:
    #
    # {"cCI"=>"M0104", "cO"=>"setDate", "n"=>"month", "v"=>"9"}
    #
    # matched this input:
    # {"cCI"=>"M0104", "n"=>"month", "v"=>"9", "age"=>"recent"}
    # 
    #
    # {
    #   {"cCI"=>"M0104", "cO"=>"setDate", "n"=>"month", "v"=>/\d+/}:
    #     { message, {"cCI"=>"M0104", "cO"=>"setDate", "n"=>"month", "v"=>"9"} }
    # }
    #
    #

    class Matcher
      # Initialize with a list a wanted statuses
      def initialize want, options={}
        @queries = {}
        want.each do |query|
          @queries[query] = nil
        end
        @m_id = options[:m_id]
      end

      def result
        @queries
      end

      def messages
        @queries.map { |query,result| result[:message] }.uniq
      end

      def items
        @queries.map { |query,result| result[:item] }.uniq
      end

      # Queries left to match?
      def done?
        @queries.values.all? { |result| result != nil }
      end

      # Check if a messages is wanted.
      # Returns true when we found all that we want.
      def process message
        ack_status = check_not_ack message
        if ack_status != nil
          return ack_status 
        end
        @queries.keys.each do |query|        # look through queries
          get_items(message).each do |item|  # look through status items in message
            matching = match? query, item
            if matching == true
              @queries[query] = { message:message, item:item }
              break
            elsif matching == false
              @queries[query] = nil
              break
            end
          end
        end
        done?      
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
            @queries = RSMP::MessageRejected.new("#{type_str} #{m_id_short} was rejected: #{message.attribute('rea')}")
            return true
          end
          return false
        end
      end
    end

    class CommandResponseMatcher < RSMP::SiteProxyWait::Matcher
      def initialize want, options={}
        super
      end

      def type_str
        "Command request"
      end

      def get_items message
        message.attributes['rvs']
      end

      def match? query, item
        return nil if query['cCI'] && query['cCI'] != item['cCI']
        return nil if query['n'] && query['n'] != item['n']
        if query['v'].is_a? Regexp
          return false if query['v'] && item['v'] !~ query['v']
        else
          return false if query['v'] && item['v'] != query['v']
        end
        true
      end
    end

    # Class for matching incoming messaging against a list of wanted statuses,
    # and flagging when everything has been matched.
    class StatusResponseMatcher < RSMP::SiteProxyWait::Matcher
      def initialize want, options={}
        super
      end

      def type_str
        "Status request"
      end

      def get_items message
        message.attributes['sS']
      end

      # Match an item against a query
      def match? query, item
        return nil if query['sCI'] && query['sCI'] != item['sCI']
        return nil if query['cO'] && query['cO'] != item['cO']
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
      matcher = CommandResponseMatcher.new options[:command_list], m_id: m_id
      collect(parent_task,options.merge(type: ['CommandResponse','MessageNotAck'], num: 1)) do |message|
        matcher.process message   # returns true when done (all queries matched)
      end
      return matcher
    rescue Async::TimeoutError
      raise RSMP::TimeoutError.new "Did not receive correct command response to #{m_id} within #{options[:timeout]}s"
    end

    def collect_status_updates_or_responses task, type, options, m_id
      matcher = StatusResponseMatcher.new options[:status_list], m_id: m_id
      collect(task,options.merge( type: [type,'MessageNotAck'], num: 1 )) do |message|
        matcher.process message   # returns true when done (all queries matched)
      end
      return matcher
    rescue Async::TimeoutError
      type_str = {'StatusUpdate'=>'update', 'StatusResponse'=>'response'}[type]
      raise RSMP::TimeoutError.new "Did not received correct status #{type_str} in reply to #{m_id} within #{options[:timeout]}s"
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
