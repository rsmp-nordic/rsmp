# Extensions to Hash providing a `deep_merge` helper.
class Hash
  def deep_merge(other_hash)
    return self unless other_hash

    merge(other_hash) do |key, old, fresh|
      if key != 'sxls' && old.is_a?(Hash) && fresh.is_a?(Hash)
        old.deep_merge(fresh)
      else
        fresh
      end
    end
  end
end
