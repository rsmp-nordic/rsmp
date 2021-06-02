class Hash 
  def deep_merge(other_hash)
    self.merge(other_hash) do |key, old, fresh|
      if old.is_a?(Hash) && fresh.is_a?(Hash)
        old.deep_merge(fresh)
      else
        fresh
      end
    end
  end
end
