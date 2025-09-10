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

    template "#{airflow_dir}/airflow.conf" do
      source 'airflow.conf.erb'
      owner user
      group group
      mode '0644'
      cookbook 'airflow'
      variables(
        port: node['airflow']['port'],
        cdomain: cdomain,
        password: airflow_password,
        data_dir: data_dir,
        log_file: log_file,
        pid_file: pid_file,
        is_cluster: cluster_info[:is_cluster],
        master_host: cluster_info[:master_host],
        is_master_here: cluster_info[:is_master_here]
      )
      notifies :restart, 'service[airflow]', :delayed
    end

    file "#{airflow_dir}/airflow.conf" do
      action :delete
      only_if do
        ::File.exist?("#{airflow_dir}/airflow.conf") &&
          !::File.read("#{airflow_dir}/airflow.conf").include?("include #{airflow_dir}/airflow.conf")
      end
    end

    file "#{airflow_dir}/airflow.conf" do
      content "include #{airflow_dir}/airflow.conf\n"
      owner user
      group group
      mode '0644'
      action :create_if_missing
    end

    service 'airflow' do
      service_name 'airflow'
      ignore_failure true
      supports status: true, restart: true, enable: true
      action [:start, :enable]
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

    service 'airflow' do
      service_name 'airflow'
      ignore_failure true
      supports status: true, enable: true
      action [:stop, :disable]
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

      node.normal['airflow']['registered'] = true
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

      node.normal['airflow']['registered'] = false
    end
    Chef::Log.info('Airflow service has been deregistered from consul')
  rescue => e
    Chef::Log.error(e.message)
  end
end
