# Cookbook:: airflow
# Provider:: config

include Airflow::Helper

action :add do
  begin
    user = new_resource.user
    group = new_resource.group
    airflow_port = new_resource.airflow_port
    cdomain = new_resource.cdomain
    ipaddress_mgt = new_resource.ipaddress_mgt
    airflow_dir = new_resource.airflow_dir
    data_dir = new_resource.data_dir
    log_file = new_resource.log_file
    pid_file = new_resource.pid_file
    airflow_env_dir = new_resource.airflow_env_dir
    airflow_secrets = new_resource.airflow_secrets
    airflow_password = airflow_secrets['pass'] unless airflow_secrets.empty?
    database_host = airflow_secrets['hostname'] unless airflow_secrets.empty?
    db_name = airflow_secrets['database'] unless airflow_secrets.empty?
    db_user = airflow_secrets['user'] unless airflow_secrets.empty?
    db_port = airflow_secrets['port'] unless airflow_secrets.empty?
    api_user = new_resource.api_user
    user_pass  = ensure_value("#{airflow_dir}/.airflow_password", length: 32)
    jwt_secret = ensure_value("#{data_dir}/jwt_secret", length: 64)

    dnf_package ['redborder-malware-pythonpyenv', 'airflow'] do
      action :upgrade
    end

    execute 'create_user' do
      command "/usr/sbin/useradd -r #{user} -s /sbin/nologin"
      ignore_failure true
      not_if "getent passwd #{user}"
    end

    directory airflow_dir do
      owner user
      group group
      mode '0755'
    end

    directory data_dir do
      owner user
      group group
      mode '0755'
    end

    template "#{airflow_dir}/airflow.cfg" do
      source 'airflow.conf.erb'
      owner user
      group group
      mode '0644'
      cookbook 'airflow'
      variables(
        airflow_dir: airflow_dir,
        data_dir: data_dir,
        log_file: log_file,
        pid_file: pid_file,
        airflow_env_dir: airflow_env_dir,
        airflow_port: airflow_port,
        cdomain: cdomain,
        ipmgt: ipaddress_mgt,
        airflow_secrets: airflow_secrets,
        airflow_password: airflow_password,
        database_host: database_host,
        db_name: db_name,
        db_user: db_user,
        db_port: db_port,
        jwt_secret: jwt_secret
      )
      notifies :restart, 'service[airflow-webserver]', :delayed
    end

    template "#{airflow_env_dir}/simple_auth_manager_passwords.json" do
      source 'simple_auth_manager_passwords.json.conf.erb'
      owner user
      group group
      mode '0644'
      cookbook 'airflow'
      variables(
        api_user: api_user,
        user_pass: user_pass
      )
      notifies :restart, 'service[airflow-webserver]', :delayed
    end

    link '/var/lib/airflow/airflow.cfg' do
      to '/etc/airflow/airflow.cfg'
      owner user
      group group
    end

    file "#{data_dir}/airflow.db_initialized" do
      content "initialized at #{Time.now}"
      owner user
      group group
      mode '0644'
      action :nothing
    end

    execute 'initialize_airflow_db' do
      command '/opt/airflow/venv/bin/airflow db migrate'
      user user
      group group
      environment(
        'AIRFLOW_HOME' => '/var/lib/airflow'
      )
      not_if { ::File.exist?("#{data_dir}/airflow.db_initialized") }
      notifies :create_if_missing, "file[#{data_dir}/airflow.db_initialized]", :immediately
    end

    %w(airflow-webserver airflow-scheduler).each do |svc|
      service svc do
        service_name svc
        supports status: true, restart: true, enable: true
        action [:enable, :start]
      end
    end

    Chef::Log.info('Airflow cookbook has been processed')
  rescue => e
    Chef::Log.error(e.message)
  end
end

action :remove do
  begin
    airflow_dir = new_resource.airflow_dir
    data_dir = new_resource.data_dir
    log_file = new_resource.log_file
    pid_file = new_resource.pid_file
    airflow_env_dir = new_resource.airflow_env_dir

    dnf_package ['redborder-malware-pythonpyenv', 'airflow'] do
      action :remove
    end

    %w(airflow-webserver airflow-scheduler).each do |svc|
      service svc do
        service_name svc
        action [:stop, :disable]
        ignore_failure true
      end
    end

    directory data_dir do
      recursive true
      action :delete
      ignore_failure true
    end

    directory airflow_dir do
      recursive true
      action :delete
      ignore_failure true
    end

    directory airflow_env_dir do
      recursive true
      action :delete
      ignore_failure true
    end

    file log_file do
      action :delete
      ignore_failure true
    end

    file pid_file do
      action :delete
      ignore_failure true
    end

    Chef::Log.info('Airflow service has been removed')
  rescue => e
    Chef::Log.error(e.message)
  end
end

action :register do
  begin
    services = [
      {
        'ID' => "airflow-web-#{node['hostname']}",
        'Name' => 'airflow-web',
        'Address' => node['ipaddress'],
        'Port' => node['airflow']['web_port'] || 9191,
      },
      {
        'ID' => "airflow-scheduler-#{node['hostname']}",
        'Name' => 'airflow-scheduler',
        'Address' => node['ipaddress_sync'],
        'Port' => node['airflow']['scheduler_port'] || 8793,
      },
    ]

    services.each do |service|
      service_key = service['Name'].gsub('-', '_')

      next if node['airflow'][service_key]['registered']

      json_query = Chef::JSONCompat.to_json(service)

      execute "Register #{service['Name']} service in consul" do
        command "curl -X PUT http://localhost:8500/v1/agent/service/register -d #{json_query.dump} &>/dev/null"
        action :nothing
      end.run_action(:run)

      node.override['airflow'][service_key]['registered'] = true
      Chef::Log.info("#{service['Name']} service has been registered in consul")
    end
  rescue => e
    Chef::Log.error("Error registering services: #{e.message}")
  end
end

action :deregister do
  begin
    services = %w(airflow-web airflow-scheduler)

    services.each do |service_name|
      service_key = service_name.gsub('-', '_')

      next unless node['airflow'][service_key]['registered']

      execute "Deregister #{service_name} service from consul" do
        command "curl -X PUT http://localhost:8500/v1/agent/service/deregister/#{service_name}-#{node['hostname']} &>/dev/null"
        action :nothing
      end.run_action(:run)

      node.override['airflow'][service_key]['registered'] = false
      Chef::Log.info("#{service_name} service has been deregistered from consul")
    end
  rescue => e
    Chef::Log.error("Error deregistering services: #{e.message}")
  end
end
