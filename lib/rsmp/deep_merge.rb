class Hash 
  def deep_merge(other_hash)
    self.merge(other_hash) do |key, old, fresh|
      if old.class.to_s == 'Hash' && fresh.class.to_s == 'Hash'
        old.deep_merge(fresh)
      else
        fresh
      end
    end
  end
end
