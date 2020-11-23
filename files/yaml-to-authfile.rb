#!/opt/puppetlabs/puppet/bin/ruby

require 'yaml'
require 'json'
require 'base64'

yaml = {}

ARGV.each do |f|
  if File.file?(f)
    # sanitize input like this
    h = YAML.load_file(f)
    if h.is_a?(Hash)
      h.each do |reg,data|
        reg = reg.downcase
        if yaml[reg].nil?
          if (['user','password'].sort == data.keys.sort)
            yaml[reg] = data
          else
            STDERR.puts "Registry #{reg} does not have all fields (#{data.inspect}) - Skipping"
          end
        else
          STDERR.puts "Registry #{reg} already present - Skipping"
        end
      end
    else
      STDERR.puts "Unable to read data of file #{f} - Skipping"
    end
  else
    STDERR.puts "File '#{f}' is no proper file - Skipping"
  end
end

res = {}

res = yaml.inject({}) do |res,(reg,data)|
  res[reg] = Base64.strict_encode64("#{data['user']}:#{data['password']}")
  res
end
puts ({ auths: res }.to_json)
