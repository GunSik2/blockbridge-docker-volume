unless data
  header "No profile information found."
  return
end

def info(pro)
  fieldset("Profile: #{pro['name']}", heading: true) do
    field 'type', pro['type']
    field 'user', pro['user']
    field 'capacity', pro['capacity']
    transport_str = pro['transport'].to_s.empty? ? 'insecure' : profile['transport']
    field 'transport', transport_str
    field 'attributes', pro['attributes']
  end
end

if data.is_a? Array
  data.each do |d|
    info d
  end
else
  info data
end
