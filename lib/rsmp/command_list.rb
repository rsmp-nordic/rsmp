module RSMP
  # Represents an RSMP command list and converts between the two common formats:
  #
  # Compact form (used in validators and helpers):
  #   RSMP::CommandList.new(:M0001, :setValue, securityCode: '1111', status: 'NormalControl')
  #
  # Raw wire Array (used in RSMP messages):
  #   [
  #     { 'cCI' => 'M0001', 'cO' => 'setValue', 'n' => 'securityCode', 'v' => '1111' },
  #     { 'cCI' => 'M0001', 'cO' => 'setValue', 'n' => 'status',       'v' => 'NormalControl' }
  #   ]
  class CommandList
    include Enumerable

    def initialize(command_code_id, command_name, values)
      @list = values.compact.map do |n, v|
        {
          'cCI' => command_code_id.to_s,
          'cO' => command_name.to_s,
          'n' => n.to_s,
          'v' => v.to_s
        }
      end
    end

    def each(&)
      @list.each(&)
    end

    def to_a
      @list
    end

    def to_h
      @list.each_with_object({}) do |item, hash|
        code = item['cCI']
        command = item['cO']
        ((hash[code] ||= {})[command] ||= {})[item['n']] = item['v']
      end
    end
  end
end
