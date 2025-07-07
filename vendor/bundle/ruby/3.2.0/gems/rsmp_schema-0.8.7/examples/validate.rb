require 'json_schemer'

message = {
  "mType" => "rSMsg",
  "mId" => "4173c2c8-a933-43cb-9425-66d4613731ed",
  "type" => "CommandRequest",
  "siteId" => [
    { "sId" => "RN+SI0001" }
  ],
  "cId" => "O+14439=481WA001",
  "arg" => [
    {
      "cCI" => "M0002",
      "n" => "timeplan",
      "cO" => "setPlan",
      "v" => "1"
    }
  ]
}

# try validating a message against our schema
schema = Pathname.new('schema/tlc/1.2.1/rsmp.json')
schemer = JSONSchemer.schema(schema)
if schemer.valid? message
  puts 'ok'
else
  schemer.validate(message).each do |item|
    puts [item['data_pointer'],item['type'],item['details']].compact.join(' ')
  end
end


