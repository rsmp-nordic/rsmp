require 'json_schemer'
require 'pathname'

Encoding.default_external = Encoding::UTF_8

SCHEMA_TLC_1_3_0 = JSONSchemer.schema(
  Pathname.new(File.expand_path('../../schemas/tlc/1.3.0/rsmp.json', __dir__))
)

def validate(message)
  errors = SCHEMA_TLC_1_3_0.validate(message).map { |e| [e['data_pointer'], e['type'], e['details']].compact }
  errors.empty? ? nil : errors.sort
end
