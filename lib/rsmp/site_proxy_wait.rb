# waiting for various types of messages and reponses from remote sites
module RSMP
  module SiteProxyWait

    def wait_for_status_updates parent_task, options={}, &send_block
      send_while_collecting parent_task, send_block do |task, m_id|
        collect_status_updates_or_responses task, 'StatusUpdate', options, m_id
      end
    end

    def wait_for_status_responses parent_task, options={}, &send_block
      send_while_collecting parent_task, send_block do |task, m_id|
        collect_status_updates_or_responses task, 'StatusResponse', options, m_id
      end
    end

    def wait_for_command_responses parent_task, options={}, &send_block
      send_while_collecting parent_task, send_block do |task, m_id|
        collect_command_responses task, options, m_id
      end
    end

    def wait_for_alarm options={}
      matching_alarm = nil
      item = collect(@task,options.merge(type: "Alarm", with_message: true, num: 1)) do |item|
        # TODO check components
        matching_alarm = nil
        alarm = item[:message]
        next if options[:aCId] && options[:aCId] != alarm.attribute("aCId")
        next if options[:aSp] && options[:aSp] != alarm.attribute("aSp")
        next if options[:aS] && options[:aS] != alarm.attribute("aS")
        matching_alarm = alarm
        break
      end
      if item
        { message: item[:message], status: matching_alarm }
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
      item = collect(parent_task,options.merge({
        type: ['CommandResponse','MessageNotAck'],
        num: 1
      })) do |item|
        message = item[:message]
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
          found = []
          # look through querues
          want.each_with_index do |query,i|
            # look through items in message
            item[:message].attributes['rvs'].each do |input|
              ok = command_match? query, input
              if ok
                result[query] = input
                found << i   # record which queries where matched succesfully
              end
            end
          end
          # remove queries that where matched
          found.sort.reverse.each do |i|
            want.delete_at i
          end
          want.empty? # any queries left to match?
        end
      end
      result
    rescue Async::TimeoutError
      raise RSMP::TimeoutError.new "Did not receive command response to #{m_id} within #{options[:timeout]}s"
    end

    def collect_status_updates_or_responses task, type, options, m_id
      want = options[:status_list]
      result = {}
      # wait for a status update
      item = collect(task,options.merge({
        type: [type,'MessageNotAck'],
        num: 1
      })) do |item|
        message = item[:message]
        if message.is_a?(MessageNotAck)
          if message.attribute('oMId') == m_id
            # set result to an exception, but don't raise it.
            # this will be returned by the task and stored as the task result
            # when the parent task call wait() on the task, the exception
            # will be raised in the parent task, and caught by rspec.
            # rspec will then show the error and record the test as failed
            m_id_short = RSMP::Message.shorten_m_id m_id, 8
            result = RSMP::MessageRejected.new "Status request #{m_id_short} was rejected: #{message.attribute('rea')}"
            next true   # done, no more messages wanted
          end
          false
        else
          found = []
          # look through querues
          want.each_with_index do |query,i|
            # look through status items in message
            item[:message].attributes['sS'].each do |input|
              ok = status_match? query, input
              if ok
                result[query] = input
                found << i   # record which queries where matched succesfully
              end
            end
          end
          # remove queries that where matched
          found.sort.reverse.each do |i|
            want.delete_at i
          end
          want.empty? # any queries left to match?
        end
      end
      result
    rescue Async::TimeoutError
      type_str = {'StatusUpdate'=>'update', 'StatusResponse'=>'response'}[type]
      raise RSMP::TimeoutError.new "Did not received status #{type_str} in reply to #{m_id} within #{options[:timeout]}s"
    end

    def status_match? query, item
      return false if query['sCI'] && query['sCI'] != item['sCI']
      return false if query['n'] && query['n'] != item['n']
      return false if query['q'] && query['q'] != item['q']
      if query['s'].is_a? Regexp
        return false if query['s'] && item['s'] !~ query['s']
      else
        return false if query['s'] && item['s'] != query['s']
      end
      true
    end

    def command_match? query, item
      return false if query['cCI'] && query['cCI'] != item['cCI']
      return false if query['n'] && query['n'] != item['n']
      if query['v'].is_a? Regexp
        return false if query['v'] && item['v'] !~ query['v']
      else
        return false if query['v'] && item['v'] != query['v']
      end
      true
    end

    def send_while_collecting parent_task, send_block, &collect_block
      m_id = RSMP::Message.make_m_id    # make message id so we can start waiting for it

      # wait for command responses in an async task
      task = parent_task.async do |task|
        collect_block.call task, m_id
      end

       # call block, it should send command request using the given m_id
      send_block.call m_id

      # wait for the response and return it, raise exception if NotAck received, it it timed out
      task.wait
    end

  end
end