require 'forwardable'

module RSMP
  # A sent request and the immutable collection produced in response.
  Exchange = Data.define(:request, :collection) do
    extend Forwardable

    def_delegators :collection, :messages, :reached, :matcher_status
  end
end
