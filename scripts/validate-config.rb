#!/usr/bin/env ruby
require 'yaml'
require 'ipaddr'
require 'uri'

location = ARGV.fetch(0)
errors = []


def yaml_files(dir)
  Dir.glob(File.join(dir, 'config', '**', '*.y{a,}ml'))
end


def load_one(dir)
  files = yaml_files(dir)
  raise "#{dir}: expected exactly one YAML config, found #{files.length}" unless files.length == 1
  YAML.safe_load(File.read(files.first), aliases: false)
end

configs = {}
Dir.children(location).sort.each do |name|
  dir = File.join(location, name)
  next unless File.directory?(dir)
  next if name == 'ci'

  begin
    if name == 'route53'
      zones = Dir.glob(File.join(dir, 'config', '**', 'zone.yml'))
      raise "#{dir}: expected at least one zone.yml" if zones.empty?
      zones.each do |zone_file|
        parsed = YAML.safe_load(File.read(zone_file), aliases: false)
        raise "#{zone_file}: missing zone mapping" unless parsed.is_a?(Hash) && parsed['zone'].is_a?(Hash)
      end
      configs[name] = { 'zones' => zones }
    else
      configs[name] = load_one(dir)
    end
  rescue => e
    errors << e.message
  end
end

begin
  ec2 = configs.fetch('ec2')
  firewall = configs.fetch('firewall')
  vpc = configs.fetch('vpc')

  cidrs = ec2.fetch('approved_ingress_cidrs')
  errors << 'ec2: approved_ingress_cidrs must not be empty' if cidrs.empty?
  errors << 'ec2: 0.0.0.0/0 is forbidden in approved_ingress_cidrs' if cidrs.include?('0.0.0.0/0')
  cidrs.each { |c| IPAddr.new(c) }

  app = ec2.fetch('application')
  errors << 'ec2: ASG must remain 1/1/1 in main' unless [app['min_size'], app['desired_capacity'], app['max_size']] == [1, 1, 1]

  artifact_uri = URI.parse(app.fetch('bootstrap').fetch('artifact_url'))
  runtime_uri = URI.parse(app.fetch('runtime_https_url'))
  errors << 'ec2: boot artifact must use HTTPS' unless artifact_uri.scheme == 'https'
  errors << 'ec2: runtime dependency must use HTTPS' unless runtime_uri.scheme == 'https'

  allowed = firewall.fetch('allowed_tls_domains')
  errors << "firewall: missing boot artifact host #{artifact_uri.host}" unless allowed.include?(artifact_uri.host)
  errors << "firewall: missing runtime host #{runtime_uri.host}" unless allowed.include?(runtime_uri.host)

  subnets = vpc.fetch('subnets')
  roles = subnets.values.group_by { |s| s.fetch('type') }
  errors << 'vpc: need at least two public subnets' unless roles.fetch('public', []).length >= 2
  %w[application database firewall].each do |role|
    errors << "vpc: missing #{role} subnet" if roles.fetch(role, []).empty?
  end

  acm = configs.fetch('acm')
  mode = acm.fetch('mode')
  unless %w[managed_dns imported].include?(mode)
    errors << "acm: unsupported mode #{mode.inspect}"
  end
  if mode == 'managed_dns'
    errors << 'acm: managed_dns requires domain_name' if acm['domain_name'].to_s.empty?
    errors << 'acm: managed_dns requires zone_name' if acm['zone_name'].to_s.empty?
  elsif acm['certificate_arn'].to_s.empty?
    errors << 'acm: imported mode requires certificate_arn'
  end
rescue => e
  errors << "cross-stack validation: #{e.message}"
end

if errors.empty?
  puts 'POC YAML/domain invariants: OK'
else
  warn errors.map { |e| "ERROR: #{e}" }.join("\n")
  exit 1
end
