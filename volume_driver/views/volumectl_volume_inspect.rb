##############################################################################
# Copyright (c) 2016, Blockbridge Networks LLC.  All rights reserved.
# Proprietary and confidential. Unauthorized copying of this file via any
# medium is strictly prohibited. Use of this source code is subject to the
# terms and conditions found in the LICENSE file.
##############################################################################

unless data
  header "No volume information found."
  return
end

def info(vol)
  fieldset("Volume: #{vol['name']}", heading: true) do
    field 'user', vol['user']
    field 'capacity', vol['capacity']
    if vol['backup']
      backup_str = nil
      if vol['s3']
        backup_str = "#{vol['s3']}/#{vol['backup']}"
      else
        backup_str = "backup:#{vol['backup']}"
      end
      field 'from backup', backup_str
    end
  end
end

if data.is_a? Array
  data.each do |d|
    info d
  end
else
  info data
end
