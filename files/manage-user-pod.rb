#!/usr/bin/env ruby
#
# This script parses a user supplied pod definition
# into a structure that can then be used to manage
# the actual pod more in a way we want it.
# There are two inputs:
#  1. the user pod yaml, defining the (user-editable) structure
#     of the pod
#  2. the system controls, enforcing all the controls that
#     shall be enforced. E.g. which ports are exposed through
#     a socket, or published.
# Format follows the official pod specification although
# only a subset of fields are supported.

require 'yaml'
require 'json'
require 'fileutils'
require 'tempfile'

class String
  def black;         "\e[30m#{self}\e[0m" end
  def red;           "\e[31m#{self}\e[0m" end
  def green;         "\e[32m#{self}\e[0m" end
  def brown;         "\e[33m#{self}\e[0m" end
  def blue;          "\e[34m#{self}\e[0m" end
  def magenta;       "\e[35m#{self}\e[0m" end
  def cyan;          "\e[36m#{self}\e[0m" end
  def gray;          "\e[37m#{self}\e[0m" end

  def bg_black;      "\e[40m#{self}\e[0m" end
  def bg_red;        "\e[41m#{self}\e[0m" end
  def bg_green;      "\e[42m#{self}\e[0m" end
  def bg_brown;      "\e[43m#{self}\e[0m" end
  def bg_blue;       "\e[44m#{self}\e[0m" end
  def bg_magenta;    "\e[45m#{self}\e[0m" end
  def bg_cyan;       "\e[46m#{self}\e[0m" end
  def bg_gray;       "\e[47m#{self}\e[0m" end

  def bold;          "\e[1m#{self}\e[22m" end
  def italic;        "\e[3m#{self}\e[23m" end
  def underline;     "\e[4m#{self}\e[24m" end
  def blink;         "\e[5m#{self}\e[25m" end
  def reverse_color; "\e[7m#{self}\e[27m" end
end


def err(str)
  puts "ERROR: #{str}"
  exit 1
end

def usage(str=nil)
  puts str if str
  err(<<EOF
USAGE: #{$0} ACTION pod-foo.user.yaml [pod-foo.system.yaml]

  ACTION: start, stop, restart, status, parse
EOF
)
end

def parse_system_controls!(system_controls)
  err("Invalid pod name '#{system_controls['name']}'") unless system_controls['name'] =~ /^[a-z0-9\-\.]+$/
  err("Requires volumes_base_dir") unless system_controls['volumes_base_dir']
  system_controls['volumes_base_dir'] = File.expand_path(system_controls['volumes_base_dir'])
  err("Requires volumes_base_dir") unless File.directory?(system_controls['volumes_base_dir'])
  err("Unsupported network_mode '#{system_controls['network_mode']}'!") if system_controls['network_mode'] && !%w{isolated host}.include?(system_controls['network_mode'])
  err("Unsupported userns '#{system_controls['userns']}'!") if system_controls['userns'] && !%w{auto keep-id host private}.include?(system_controls['userns'])

  system_controls['containers'] ||= {}
  system_controls['volumes_containers_gid_share'] ||= true
  system_controls['socket_ports'] ||= {}
  system_controls['socket_ports'] = system_controls['socket_ports'].keys.each_with_object({}) do |port,res|
    port_vals = system_controls['socket_ports'][port]
    port = port.to_i
    err("Invalid socket ports: '#{port}'") unless port > 0
    port_vals['dir'] ||= File.join(system_controls['volumes_base_dir'],'tmp/run')
    err("Non-writable socket port directory: '#{port_vals['dir']}'") unless File.writable?(port_vals['dir'])
    port_vals['mode'] ||= '0777'
    res[port] = port_vals
  end
  system_controls['exposed_ports'] = Array(system_controls['exposed_ports'])
  system_controls['exposed_ports'].each do |port|
    err("Invalid exposed port: #{port}") unless port =~ /^\d+\/(tcp|udp)$/
  end
  if system_controls['pidfile'] && !File.writable?(File.dirname(system_controls['pidfile']))
    err("Can't write pidfile '#{system_controls['pidfile']}'")
  end
  system_controls['logging'] ||= {}
  system_controls['logging'] = { 'log-driver' => 'journald' }.merge(system_controls['logging'])
end

def parse_volumes(volumes, volumes_base_dir)
  return {} unless volumes
  volumes.each_with_object({}) do |vol,res|
    err("Error with volume (#{vol.inspect}) - must contain name") if vol['name'].nil?
    err("Error with volume (#{vol.inspect}) - name already used") if res[vol['name']]
    if vol['hostPath'] && vol['hostPath']['path']&& vol['hostPath']['type'] == 'Directory'
      res[vol['name']] = File.join(volumes_base_dir, File.expand_path(vol['hostPath']['path']))
      err("Non-existing volumes directory: '#{res[vol['name']]}'") unless File.directory?(res[vol['name']])
    elsif vol['emptyDir'] && vol['emptyDir']['medium'] == 'Memory'
      res[vol['name']] = 'tmpfs'
    else
      err("Only hostpath (type: Directory) volumes are supported")
    end
  end
end

def parse_pod(spec)
  defaults = {
    'securityContext' => {},
  }
  spec.keys.each_with_object(defaults) do |k,res|
    if ['hostname'].include?(k)
      res[k] = spec[k]
    end
  end
end

def parse_containers(containers, volumes, pod_specs, system_controls)
  socket_ports = system_controls['socket_ports'].dup
  system_controls['socket_ports'] = {}
  exposed_ports = system_controls['exposed_ports'].dup
  system_controls['exposed_ports'] = []

  containers.each_with_object({}) do |con,res|
    err("Error with container (#{con.inspect}) - must contain name") if con['name'].nil?
    err("Error with container #{con['name']} - name already used") if res[con['name']]
    err("Error with container #{con['name']} - must contain immage") unless con['image']
    con['image'] = "#{con['image']}:latest" unless con['image'] =~ /:/
    res[con['name']] = { 'image' => con['image'] }
    system_controls['containers'][con['name']] ||= {}

    vol_mounts = Array(con['volumeMounts'])
    res[con['name']]['volumeMounts'] = vol_mounts.each_with_object([]) do |vol,obj|
      err("Error with container #{con['name']} - volume '#{vol['name']}' is not known in volumes!") unless volumes[vol['name']]
      err("Error with container #{con['name']} - volume '#{vol['name']}' requires mountPath") unless vol['mountPath']

      obj << vol
    end

    system_controls['containers'][con['name']] ||= {}

    envs = Array(con['env'])
    res[con['name']]['env'] = envs.each_with_object({}) do |env, obj|
      err("Error with environment '#{env['name']} - requires name & value!") if env['name'].nil? || env['value'].nil?
      obj[env['name']] = env['value']
    end

    res[con['name']]['env_files'] = system_controls['containers'][con['name']]['env_files'] || []
    res[con['name']]['env_files'].each do |f|
      error("Env-file '#{f}' doesn not exist!") unless File.file?(env_file)
    end
    if d = system_controls['container_env_dir']
      env_file = File.join(d,"#{system_controls['name']}-#{con['name']}.env")
      if File.file?(env_file)
        res[con['name']]['env_files'] << env_file
      end
    end
    Array(con['ports']).each do |port|
      if socket_ports.keys.include?(port['containerPort'].to_i) && port['protocol'] == 'TCP'
        system_controls['socket_ports'][port['containerPort'].to_i] = socket_ports.delete(port['containerPort'].to_i)
      else
        if exposed_ports.include?("#{port['hostPort'].to_i}/#{(port['protocol']||'tcp').downcase}")
          system_controls['exposed_ports'][con['name']] << "#{port['hostPort'].to_i}:#{port['containerPort'].to_i}/#{(port['protocol']||'tcp').downcase}"
        else
          puts "Ignoring port specification '#{port.inspect}', since it's not exposed nor passed through socket"
        end
      end
    end
    res[con['name']]['securityContext'] = con['securityContext'] || {}

    res[con['name']]['log-driver'] ||= system_controls['containers'][con['name']]['log-driver'] || system_controls['logging']['log-driver']
    res[con['name']]['log-opt'] ||= system_controls['containers'][con['name']]['log-opt'] || system_controls['logging']['log-opt']

    # figure out the user to run as
    user = system_controls['containers'][con['name']]['user']
    group = nil
    if user && user =~ /:/
      user, group = user.split(':',2)
    end
    user ||= res[con['name']]['securityContext']['runAsUser'] || pod_specs['securityContext']['runAsUser']
    group ||= res[con['name']]['securityContext']['runAsGroup'] || pod_specs['securityContext']['runAsGroup']
    if user.nil? || group.nil?
      uid, gid = user_group_id(con['image'])
    end
    if group || gid
      user = "#{user || uid}:#{group || gid}"
    else
      user = user || uid
    end
    user ||= 'root'

    # validate non-root
    allowed_to_run_as_root = (system_controls['runAsNonRoot'] == false) || (system_controls['containers'][con['name']]['runAsNonRoot'] == false)
    if !allowed_to_run_as_root && user =~ /^(root|0)(:|$)/
      err("Running container #{con['name']} as root is not allowed!")
    end

    # if we have volumes, and volumes_containers_gid_share is enabled, we should either run as the same GID (either 0 without keep-id or the effective user-id)
    if !res[con['name']]['volumeMounts'].empty? && \
        (system_controls['containers'][con['name']]['volumes_containers_gid_share'] || system_controls['volumes_containers_gid_share'])
      group = if system_controls['userns'] == 'keep-id'
        Process.egid
      else
        0
      end
      user = user.split(':',2).first + ":#{group}"
    end
    res[con['name']]['user'] = user
  end
end

def get_pod_id(name)
  `podman pod exists '#{name}'`
  if $?.success?
    `podman pod ps --format '{{.ID}} {{.Name}}' --filter 'name=#{name}' | grep -E ' #{name}$' | cut -d' ' -f 1`.chomp
  else
    ''
  end
end

def stop_pod(pod_id, name)
  print "Stopping pod #{name}: "
  if `podman pod ps --format '{{.ID}}' --filter 'id=#{pod_id}' --filter 'status=running'` == pod_id
    `/usr/bin/podman pod stop -t 20 "#{pod_id}`
    print "requested ".magenta
    if `podman pod ps --format '{{.ID}}' --filter 'id=#{pod_id}' --filter 'status=running'` == pod_id
      print "still running: killing ".cyan
      `/usr/bin/podman pod kill "#{pod_id}"`
      unless $?.success?
        puts "ERROR while killing pod #{name}".red
        exit 120
      end
    end
  end
  puts "DONE".green
  print "Removing pod #{name}: "
  `/usr/bin/podman pod rm -f "#{name}"`
  puts "DONE".green
end

def pod_name_str(pod_name, first_con_id)
  if first_con_id
    pod_name
  else
    "new:#{pod_name}"
  end
end

def user_group_id(image)
  res = `podman inspect -t image #{image}`
  unless $?.success?
    res = `podman pull -q #{image} > /dev/null && podman inspect -t image #{image}`
    unless $?.success?
      err("Unable to inspect & pull image '#{image}'")
    end
  end
  images = JSON.parse(res)
  images.first['User'].split(':',2)
end

def socket_pod_str(name, con_name, port, index, first_con_id, port_vals, system_controls)
  res = "/usr/bin/podman run -d --pod '#{pod_name_str(name,first_con_id)}' --name '#{con_name}' -v #{port_vals['dir']}:/run/pod:rw"
  if system_controls['network_mode'] == 'isolated'
    if index == 0
      res << " --network=none"
    else
      res << " --network=container:#{first_con_id}"
    end
  elsif system_controls['network_mode']
    res << " --network=#{system_controls['network_mode']}"
  end
  if system_controls['userns']
    res << " --userns=#{system_controls['userns']}"
  end
  res << " --read-only=true --security-opt=no-new-privileges"
  if port_vals['security-opt-label-type']
    res << " --security-opt=label=type:#{port_vals['security-opt-label-type']}.process"
  end
  res << " --log-driver=#{system_controls['logging']['log-driver']}"
  if system_controls['logging']['log-opt']
    system_controls['logging']['log-opt'].each do |k,v|
      if k == 'tag'
        res << " --log-opt=#{k}=#{v}-#{con_name}"
      else
        res << " --log-opt=#{k}=#{v}"
      end
    end
  end
  res << " registry.code.immerda.ch/immerda/container-images/socat:7"
  res << " UNIX-LISTEN:/run/pod/#{port},fork,end-close,reuseaddr,mode=#{port_vals['mode']} TCP:127.0.0.1:#{port}"
  res
end

def pod_cmd(pod_name, con_name, pod_specs, con_values, first_con_id, volumes, system_controls)
  res = "/usr/bin/podman run -d --pod '#{pod_name_str(pod_name, first_con_id)}' --name '#{con_name}'"
  system_controls['exposed_ports'].each do |port|
    res << " --publish #{port}"
  end
  con_values['volumeMounts'].each do |vol|
    if volumes[vol['name']] == 'tmpfs'
      res << " --tmpfs #{vol['mountPath']}"
    else
      str = " --volume #{volumes[vol['name']]}:#{vol['mountPath']}"
      if vol['readOnly']
        str << ":ro,Z"
      else
        str << ":rw,Z"
      end
    end
    res << str
  end

  unless con_values['env'].empty?
    env_file = Tempfile.new("env-#{pod_name}-#{con_name}", system_controls['tmp_dir'])
    con_values['env'].each do |k,v|
      env_file.puts "#{k}=#{v}"
    end
    env_file.close
    res << " --env-file #{env_file.path}"
  end
  con_values['env_files'].each do |f|
    res << " --env-file #{f}"
  end
  if system_controls['network_mode'] == 'isolated'
    if index == 0
      res << " --network=none"
    else
      res << " --network=container:#{first_con_id}"
    end
  elsif system_controls['network_mode']
    res << " --network=#{system_controls['network_mode']}"
  end
  if pod_specs['hostname']
    res << " --hostname #{pod_specs['hostname']}"
  end
  if system_controls['containers'][con_name]['readOnlyRootFilesystem'] || con_values['securityContext']['readOnlyRootFilesystem']
    res << " --read-only=true"
  else
    res << " --read-only=false"
  end
  if system_controls['userns']
    res << " --userns=#{system_controls['userns']}"
  end
  if con_values['user']
    res << " --user=#{con_values['user']}"
  end
  if p = system_controls['containers'][con_name]['seccompProfile']
    res << " --security-opt=seccomp=#{p}"
  end
  Array(system_controls['containers'][con_name]['security_opt']).each do |so|
    res << " --security-opt=#{so}"
  end
  res << " --log-driver=#{con_values['log-driver']}"
  if con_values['log-opt']
    con_values['log-opt'].each do |k,v|
      if k == 'tag'
        res << " --log-opt=#{k}=#{v}-#{con_name}"
      else
        res << " --log-opt=#{k['log-opt']}=#{v}"
      end
    end
  end
  if s = system_controls['containers'][con_name]['systemd']
    res << " --systemd=#{s}"
  end
  res << " #{con_values['image']}"
  res << " #{con_values['command']}" if con_values['command']
  res
end

def start_pod(pod_specs, containers, volumes, system_controls)
  name = system_controls['name']
  puts "Starting pod #{name}:"
  puts
  first_con_id = nil
  system_controls['socket_ports'].keys.each_with_index do |port,index|
    con_name = "socket-#{port}-#{name}"
    print "  * " + "#{con_name} ".cyan
    socket_file = File.join(system_controls['socket_ports'][port]['dir'],port.to_s)
    if File.symlink?(socket_file)
      puts "FATAL: #{socket_file} is a symlink".red
      exit 255
    end
    print "(#{socket_file}) "
    if File.exists?(socket_file)
      File.delete(socket_file)
    end
    cmd = socket_pod_str(name, con_name, port, index, first_con_id, system_controls['socket_ports'][port], system_controls)
    `#{cmd}`
    unless $?.success?
      puts "ERROR".red
      exit 128
    end
    puts "\u2713 ".green
    first_con_id ||= `podman ps --format={{.ID}} -f name=socket-#{port}-#{name}`
  end
  last_con_name = nil
  containers.each do |con_name, con_values|
    print "  * " + "#{con_name} ".cyan
    cmd = pod_cmd(name, con_name, pod_specs, con_values, first_con_id, volumes, system_controls)
    `#{cmd}`
    unless $?.success?
      puts "ERROR".red
      exit 128
    end
    puts "\u2713 ".green
    first_con_id ||= `podman ps --format={{.ID}} -f name=#{con_name}`
    last_con_name = con_name
  end
  puts
  puts "ALL DONE".green
  if system_controls['pidfile']
    pid_file = `podman container inspect #{last_con_name} -f '{{.ConmonPidFile}}'`.chomp
    i=0
    # might take a while until it's here
    while !File.exist?(pid_file) && i < 10 do
      i+=1
      sleep 1
    end
    FileUtils.copy_file(pid_file, system_controls['pidfile'])
  end
end

def dump_yaml(containers, pod_specs, volumes, system_controls)
  puts "# containers"
  puts YAML.dump(containers)
  puts
  puts "# pod_specs"
  puts YAML.dump(pod_specs)
  puts
  puts "# volumes"
  puts YAML.dump(volumes)
  puts
  puts "# system_controls"
  puts YAML.dump(system_controls)
end

action = ARGV.shift
usage("Unsupported action '#{action}'!") unless %w{parse start stop restart status}.include?(action)
usage if ARGV.empty?
user_yaml = File.expand_path(ARGV.shift)
err("Can't read '#{user_yaml}'") unless File.file?(user_yaml)
user_pod = YAML.load_file(user_yaml)

system_controls = if ARGV.empty?
  # the only required option and we drop encorcement
  { 'volumes_base_dir' => '/' }
else
  system_yaml = File.expand_path(ARGV.shift)
  err("Can't read '#{system_yaml}'") unless File.file?(system_yaml)
  YAML.load_file(system_yaml)
end

unless user_pod.is_a?(Hash) && user_pod['spec'] && user_pod['spec']['containers']
  err("Requires spec.containers in yaml '#{user_yaml}'!")
end
unless system_controls.is_a?(Hash)
  err("Requires a yaml for system controls!")
end
system_controls['name'] ||= user_pod['metadata']['name'] if user_pod['metadata']

parse_system_controls!(system_controls)

volumes = parse_volumes(user_pod['spec']['volumes'], system_controls['volumes_base_dir'])
pod_specs = parse_pod(user_pod['spec'])
containers = parse_containers(user_pod['spec']['containers'], volumes, pod_specs, system_controls)

if action == 'parse'
  dump_yaml(containers, pod_specs, volumes, system_controls)
  exit 0
end


pod_id = get_pod_id(system_controls['name'])
if action == 'status'
  print "Pod #{system_controls['name']} is "
  if pod_id.empty?
    puts "not".red + " present..."
    exit 1
  else
    puts "present as #{pod_id.green}"
    exit 0
  end
elsif action == 'stop'
  if pod_id.empty?
    puts "No pod #{system_controls['name']} "+"running".cyan
    exit 0
  else
    stop_pod(pod_id, system_controls['name'])
    if system_controls['tmp_dir']
      Dir[File.join(system_controls['tmp_dir'],"env-#{system_controls['name']}-*")].each do |env_file|
        File.delete(env_file) if File.file?(env_file)
      end
    end
    exit 0
  end
# restart is the same
elsif action =~ /start$/
  stop_pod(pod_id, system_controls['name']) unless pod_id.empty?
  start_pod(pod_specs, containers, volumes, system_controls)
  exit 0
end
