module RSMP
  module SXL
    module Processing
      # Natural sorting for identifiers containing decimal digit sequences.
      module NaturalSort
        def self.key(value)
          value.scan(/\d+|\D+/).map do |part|
            if part.match?(/\A\d+\z/)
              [0, part.to_i, part.length]
            else
              [1, part]
            end
          end
        end

        def self.sort(values)
          values.sort_by { |value| key(value) }
        end
      end
    end
  end
end
