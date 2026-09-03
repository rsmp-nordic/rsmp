module RSMP
  module SXL
    module Processing
      # Rejects component types or message codes owned by more than one SXL.
      module ConflictChecker
        def self.check!(documents)
          check_definitions!(documents, :component_types, 'component type')
          check_definitions!(documents, :message_codes, 'message code')
        end

        def self.check_definitions!(documents, collection, label)
          owners = {}
          documents.each do |document|
            document.public_send(collection).each do |definition|
              previous = owners[definition.id]
              if previous
                raise Error,
                      "Conflicting #{label} #{definition.id.inspect} in " \
                      "#{previous[:document].name} and #{document.name}"
              end
              owners[definition.id] = { document: document, definition: definition }
            end
          end
        end

        private_class_method :check_definitions!
      end
    end
  end
end
