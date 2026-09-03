module RSMP
  module SXL
    module Processing
      # Dependency graph validation shared by resolution and manifest verification.
      module DependencyGraph
        def self.cycle(documents)
          by_name = documents.to_h { |document| [document.name, document] }
          visited = {}
          stack = []
          by_name.each_key do |name|
            found = visit(name, by_name, visited, stack)
            return found if found
          end
          nil
        end

        def self.visit(name, documents, visited, stack)
          return stack[stack.index(name)..] + [name] if stack.include?(name)
          return nil if visited[name]

          visited[name] = true
          stack << name
          documents.fetch(name).dependencies.each_key do |dependency|
            next unless documents.key?(dependency)

            found = visit(dependency, documents, visited, stack)
            return found if found
          end
          stack.pop
          nil
        end

        private_class_method :visit
      end
    end
  end
end
