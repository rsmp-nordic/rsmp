module RSMP
  module SXL
    module Processing
      # Resolves root requirements to a deterministic set of exact SXL versions.
      class Resolver
        def initialize(catalogue)
          @catalogue = catalogue
          @diagnostics = []
        end

        def resolve(root_requirements)
          constraints = Hash.new { |hash, key| hash[key] = [] }
          root_requirements.each do |name, requirement|
            Document.validate_name!(name)
            constraints[name] << requirement
          end
          raise Error, 'At least one root SXL is required' if constraints.empty?

          solution = search({}, constraints)
          return sorted(solution.values) if solution

          detail = @diagnostics.uniq.first(3).join('; ')
          raise Error, "Cannot resolve SXL dependencies#{": #{detail}" unless detail.empty?}"
        end

        private

        def search(selected, constraints)
          return nil unless selected_versions_valid?(selected, constraints)

          unresolved = NaturalSort.sort(constraints.keys.reject { |name| selected.key?(name) })
          return selected if unresolved.empty?

          name = unresolved.first
          candidates = @catalogue.candidates(name, constraints[name])
          record_missing_candidate(name, constraints[name]) if candidates.empty?

          candidates.each do |document|
            solution = search_candidate(name, document, selected, constraints)
            return solution if solution
          end
          nil
        end

        def search_candidate(name, document, selected, constraints)
          next_selected = selected.merge(name => document)
          next_constraints = copy_constraints(constraints)
          document.dependencies.each_pair do |dependency_name, requirement|
            next_constraints[dependency_name] << requirement
          end

          cycle = DependencyGraph.cycle(next_selected.values)
          if cycle
            @diagnostics << "cyclic dependency #{cycle.join(' -> ')}"
            return nil
          end

          search(next_selected, next_constraints)
        end

        def selected_versions_valid?(selected, constraints)
          selected.each_pair do |name, document|
            next if constraints[name].all? { |requirement| requirement.satisfied_by?(document.version) }

            requirements = constraints[name].map(&:source).join(', ')
            @diagnostics << "#{name} #{document.version_string} does not satisfy #{requirements}"
            return false
          end
          true
        end

        def record_missing_candidate(name, requirements)
          available = @catalogue.versions(name)
          if available.empty?
            @diagnostics << "no versions available for #{name}"
          else
            expected = requirements.map(&:source).join(', ')
            @diagnostics << "no version of #{name} satisfies #{expected} (available: #{available.join(', ')})"
          end
        end

        def copy_constraints(constraints)
          constraints.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(name, requirements), copy|
            copy[name] = requirements.dup
          end
        end

        def sorted(documents)
          documents.sort_by { |document| NaturalSort.key(document.name) }
        end
      end
    end
  end
end
