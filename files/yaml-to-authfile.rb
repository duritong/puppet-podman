#!/opt/puppetlabs/puppet/bin/ruby
#
# Iterate over each file passed as
# argument and merge each auth into
# a containers auth file
# inut is yaml, like:
# registry.example.com:
#   user: myself
#   password: super_secret
# In case of double registries in
# different files: entry in earlier file wins

require 'yaml'
require 'json'
require 'base64'

all_yaml = ARGV.each_with_object({}) do |f, yaml|
  if File.file?(f)
    # sanitize input like this
    h = YAML.load_file(f)
    if h.is_a?(Hash)
      h.each do |reg, data|
        reg = reg.downcase
        if yaml[reg].nil?
          # rubocop:disable Metrics/BlockNesting
          if ['user', 'password'].sort == data.keys.sort
            yaml[reg] = { auth: Base64.strict_encode64("#{data['user']}:#{data['password']}") }
          else
            STDERR.puts "Registry #{reg} does not have all fields (#{data.inspect}) - Skipping"
          end
          # rubocop:enable Metrics/BlockNesting
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

puts({ auths: all_yaml }.to_json)
