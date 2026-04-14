module RSMP
  # Represents an RSMP status list and converts between the two common formats:
  #
  # Compact Hash (symbol or string keys):
  #   { S0014: [:status, :source] }
  #   { 'S0014' => ['status', 'source'] }
  #
  # Raw wire Array (used in RSMP messages):
  #   [{ 'sCI' => 'S0014', 'n' => 'status' }, { 'sCI' => 'S0014', 'n' => 'source' }]
  class StatusList
    include Enumerable

    def initialize(input)
      @list = case input
              when StatusList
                input.to_a
              when Array
                input
              when Hash
                input.flat_map do |code, names|
                  names.map { |name| { 'sCI' => code.to_s, 'n' => name.to_s } }
                end
              else
                raise ArgumentError, "StatusList requires an Array, Hash, or StatusList, got #{input.class}"
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
        code = item['sCI']
        name = item['n']
        (hash[code] ||= []) << name
      end
    end
  end
end
