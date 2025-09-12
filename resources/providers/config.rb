# Cookbook:: airflow
# Provider:: config

include Airflow::Helper

action :add do
  begin
    user = new_resource.user
    group = new_resource.group
    cdomain = new_resource.cdomain
    airflow_dir = new_resource.airflow_dir
    data_dir = new_resource.data_dir
    log_file = new_resource.log_file
    pid_file = new_resource.pid_file
    airflow_hosts = new_resource.airflow_hosts
    airflow_secrets = new_resource.airflow_secrets
    airflow_password = airflow_secrets['pass'] unless airflow_secrets.empty?
    cluster_info = get_cluster_info(airflow_hosts, node['hostname'])

    dnf_package 'airflow' do
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

    template '/etc/airflow/airflow.cfg' do
      source 'airflow.conf.erb'
      owner 'airflow'
      group 'airflow'
      mode '0644'
      variables(
        airflow_dir: airflow_dir,
        data_dir: data_dir,
        log_file: log_file,
        pid_file: pid_file,
        cdomain: cdomain,
        airflow_hosts: airflow_hosts,
        airflow_secrets: airflow_secrets,
        airflow_password: airflow_secrets['pass'],
        cluster_info: cluster_info
      )
    end

    file "#{airflow_dir}/airflow.cfg" do
      action :delete
      only_if do
        ::File.exist?("#{airflow_dir}/airflow.cfg") &&
          !::File.read("#{airflow_dir}/airflow.cfg").include?("include #{airflow_dir}/airflow.cfg")
      end
    end

    file "#{airflow_dir}/airflow.cfg" do
      content "include #{airflow_dir}/airflow.cfg\n"
      owner user
      group group
      mode '0644'
      action :create_if_missing
    end

    execute 'initialize_airflow_db' do
      command "airflow db migrate"
      user new_resource.user      # <-- el usuario que corre Airflow (ej: 'airflow')
      group new_resource.group
      environment(
        'AIRFLOW_HOME' => new_resource.airflow_dir,
        'AIRFLOW__CORE__SQL_ALCHEMY_CONN' => "postgresql+psycopg2://#{new_resource.airflow_secrets['user']}:#{new_resource.airflow_secrets['pass']}@postgres/#{new_resource.cdomain}"
      )
      not_if { ::File.exist?("#{new_resource.data_dir}/airflow.db_initialized") }
    end
    
    file "#{new_resource.data_dir}/airflow.db_initialized" do
      content "initialized at #{Time.now}"
      owner new_resource.user
      group new_resource.group
      mode '0644'
      action :create_if_missing
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
    unless node['airflow']['registered']
      query = {}
      query['ID'] = "airflow-#{node['hostname']}"
      query['Name'] = 'airflow'
      query['Address'] = node['ipaddress_sync']
      query['Port'] = node['airflow']['port']
      json_query = Chef::JSONCompat.to_json(query)

      execute 'Register service in consul' do
        command "curl -X PUT http://localhost:8400/v1/agent/service/register -d '#{json_query}' &>/dev/null"
        action :nothing
      end.run_action(:run)

      node.override['airflow']['registered'] = true
    end
    Chef::Log.info('Airflow service has been registered in consul')
  rescue => e
    Chef::Log.error(e.message)
  end
end

action :deregister do
  begin
    if node['airflow']['registered']
      execute 'Deregister service in consul' do
        command "curl -X PUT http://localhost:8400/v1/agent/service/deregister/airflow-#{node['hostname']} &>/dev/null"
        action :nothing
      end.run_action(:run)

      node.override['airflow']['registered'] = false
    end
    Chef::Log.info('Airflow service has been deregistered from consul')
  rescue => e
    Chef::Log.error(e.message)
  end
end
