# Applies the settings that the deployment manages and creates the first
# administrator. Runs with `rails r` after the database is installed or migrated.
# Values are read from the environment, never interpolated into code.

require 'socket'

def env(name)
  ENV[name].to_s.strip
end

# Elasticsearch: on when ELASTICSEARCH_HOST is set, unless ELASTICSEARCH_ENABLED
# is false. Without it Zammad falls back to database search.
if env('ELASTICSEARCH_HOST').present? && env('ELASTICSEARCH_ENABLED') != 'false'
  host = env('ELASTICSEARCH_HOST')
  port = (env('ELASTICSEARCH_PORT').presence || '9200').to_i

  Setting.set('es_url', "#{env('ELASTICSEARCH_SCHEMA').presence || 'http'}://#{host}:#{port}")
  Setting.set('es_index', env('ELASTICSEARCH_NAMESPACE').presence || 'zammad')
  Setting.set('es_user', env('ELASTICSEARCH_USER'))
  Setting.set('es_password', ENV['ELASTICSEARCH_PASS'].to_s)
  puts "Elasticsearch: #{Setting.get('es_url')}"

  deadline = Time.zone.now + 10.minutes
  begin
    Socket.tcp(host, port, connect_timeout: 5).close
  rescue SystemCallError, SocketError, IOError
    abort "Elasticsearch at #{host}:#{port} did not accept connections within 10 minutes." if Time.zone.now > deadline

    puts "Waiting for Elasticsearch at #{host}:#{port}..."
    sleep 5
    retry
  end
else
  Setting.set('es_url', '')
  puts 'Elasticsearch: off'
end

# Links in notifications and the web app follow the service's primary domain.
if env('ZAMMAD_FQDN').present?
  Setting.set('fqdn', env('ZAMMAD_FQDN'))
  Setting.set('http_type', env('ZAMMAD_HTTP_TYPE').presence || 'https')
  puts "URL: #{Setting.get('http_type')}://#{Setting.get('fqdn')}"
end

# Outgoing notifications: a container install activates an SMTP notification
# channel with the placeholder host host.example.com. Point that placeholder at
# the linked mail relay. A channel configured in Zammad is never changed.
if env('SMTP_HOST').present?
  channel = Channel.where(area: 'Email::Notification', active: true).detect do |item|
    item.options.dig(:outbound, :adapter) == 'smtp' &&
      item.options.dig(:outbound, :options, :host) == 'host.example.com'
  end
  if channel
    channel.options[:outbound][:options] = {
      host:                 env('SMTP_HOST'),
      port:                 (env('SMTP_PORT').presence || '25').to_i,
      user:                 '',
      password:             '',
      ssl:                  false,
      ssl_verify:           false,
      enable_starttls_auto: false,
    }
    UserInfo.ensure_current_user_id { channel.save! }
    puts "Notifications: sent through #{env('SMTP_HOST')}:#{channel.options[:outbound][:options][:port]}"
  end
end

# First administrator. The getting started page lets anyone who opens a new
# Zammad create the administrator, so it is created here before any web pod
# serves a request, and the page is never offered.
if Setting.get('import_mode')
  puts 'An import is running. No administrator created.'
elsif User.admin_user_exists?(except_user_id: [1])
  puts 'An administrator already exists. No administrator created.'
else
  email = env('ZAMMAD_ADMIN_EMAIL').downcase
  password = ENV['ZAMMAD_ADMIN_PASSWORD'].to_s
  abort 'No administrator exists and ZAMMAD_ADMIN_EMAIL is empty.' if email.empty?
  if User.exists?(login: email) || User.exists?(email: email)
    abort "No administrator exists and #{email} already belongs to another user. Set another administrator email."
  end

  PasswordPolicy.new(password).valid!

  UserInfo.ensure_current_user_id do
    User.create!(
      login:     email,
      email:     email,
      firstname: env('ZAMMAD_ADMIN_FIRSTNAME').presence || 'Admin',
      lastname:  env('ZAMMAD_ADMIN_LASTNAME'),
      password:  password,
      active:    true,
      role_ids:  Role.where(name: %w[Admin Agent]).pluck(:id),
      group_ids: Group.pluck(:id),
    )
  end
  Setting.set('system_init_done', true)
  begin
    TextModule.load('en-us')
  rescue => e
    warn "Unable to load text modules: #{e.message}"
  end
  puts "Created the first administrator: #{email}"
end
