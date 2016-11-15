##############################################################################
# Copyright (c) 2016, Blockbridge Networks LLC.  All rights reserved.
# Proprietary and confidential. Unauthorized copying of this file via any
# medium is strictly prohibited. Use of this source code is subject to the
# terms and conditions found in the LICENSE file.
##############################################################################


e = data

case e
when RuntimeSuccess
  msg = e.message.word_wrap(76)
  puts msg.each_line { |line| puts "  #{line}" }

when Clamp::UsageError
  msg = e.message.word_wrap(70)
  msg.lines.each_with_index do |line, idx|
    if idx == 0
      puts "ERROR: #{line}"
    else
      puts "       #{line}"
    end
  end
  puts ""
  puts "See: '#{e.command.invocation_path} --help'"

when RuntimeError
  msg = e.message.word_wrap(70)
  msg.lines.each_with_index do |line, idx|
    if idx == 0
      puts "ERROR: #{line}"
    else
      puts "       #{line}"
    end
  end

when RestClient::NotFound
  response = MultiJson.load(e.response, symbolize_keys: true) rescue nil
  if response
    puts "ERROR: #{response[:error]}"
  else
    puts "ERROR: Volume not found"
  end

when RestClient::BadRequest
  response = MultiJson.load(e.response, symbolize_keys: true) rescue nil
  if response
    puts "ERROR: #{response[:error]}"
  else
    puts "ERROR: #{e.command_instance.invocation_path} failed with a bad request"
  end

  puts ""
  puts "See: '#{e.command_instance.invocation_path} --help'"

when RestClient::Conflict
  response = MultiJson.load(e.response, symbolize_keys: true) rescue nil
  if response
    puts "ERROR: #{response[:error]}"
  else
    puts "ERROR: Volume conflict."
  end

when Clamp::HelpWanted
  # display help with our custom builder.
  puts e.command.class.help(e.command.invocation_path,
                            HelpBuilder.new(opts))

else
  if ENV['BLOCKBRIDGE_DIAGS']
    puts "UNHANDLED EXCEPTION: #{e.message.chomp} (#{e.class})"
  else
    puts "ERROR: #{e.message.chomp}"
  end
end
