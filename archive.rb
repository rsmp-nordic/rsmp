# Archive of log items, which can be messages or info items.
# All items are timestamped, and stored chronologically.

module RSMP
  class Archive
    attr_reader :items

    def initialize
      @items = []
      @mutex = Mutex.new
      @condition_variable = ConditionVariable.new
    end

    def self.prepare_item item
      raise ArgumentError unless item.is_a? Hash
    
      now_obj = RSMP.now_object
      now_str = RSMP.now_string(now_obj)

      cleaned = item.select { |k,v| [:level,:ip,:site_id,:str,:message,:exception].include? k }
      cleaned[:timestamp] = now_obj
      cleaned[:direction] = item[:message].direction if item[:message]
      
      cleaned
    end

    def add item
      @mutex.synchronize do
        @items << item
        @condition_variable.broadcast
      end
    end


    # extractor that looks for specific messages when they arrive
    # matching messages are stored in the extractor
    # once it has collected what it needs, it triggers the condition variable
    # and the client wakes up

    # wait for message, optionally with specific search criteria.
    # uses a mutex and condition variable to sleep until messages arrive.
    # when we wake we check messages received since we went to sleep.
    def wait_for_messages options, &block
      num = options[:num] || 1
      earliest = options[:earliest]
      found = []
      start = Time.now
      batch_earliest = earliest
      find_options = { type: options[:type], earliest: batch_earliest, with_message: true, num: num }

      @mutex.synchronize do
        loop do
          now = Time.now
          batch = find(find_options,&block).map { |item| item[:message]}
          found = found + batch
          batch_earliest = now
          left = options[:timeout] + (start - Time.now)
          return found, found.size if found.size >= num or left <= 0
          @condition_variable.wait(@mutex,left)
        end
      end
      nil
    end

    def wait_for_message options, &block
      found = wait_for_messages(options.merge(num:1), &block) || []
      found.first
    end

    private

    def find options, &block
      # search backwards from newest to older, stopping once messages
      # are older that options[:earliest]
      out = []
      @items.reverse_each do |item|
        break if options[:earliest] && item[:timestamp] < options[:earliest]
        next if options[:type] && (item[:message] == nil || (item[:message].type != options[:type]))
        next if options[:with_message] && !(item[:direction] && item[:message])
        next if block_given? && block.call != true
        out.unshift item
      end
      out
    end
  end
end