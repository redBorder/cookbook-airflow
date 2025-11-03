# Cookbook:: airflow
# Provider:: triggerer

include Airflow::Triggerer

action :add do
  begin
    service 'airflow-triggerer' do
      service_name 'airflow-triggerer'
      ignore_failure true
      supports status: true, restart: true, enable: true
      action [:enable, :start]
    end

    Chef::Log.info('Airflow Triggerer has been processed')
  rescue => e
    Chef::Log.error(e.message)
  end
end

action :remove do
  begin
    service 'airflow-triggerer' do
      service_name 'airflow-triggerer'
      ignore_failure true
      supports status: true, enable: true
      action [:stop, :disable]
    end

    Chef::Log.info('Airflow Triggerer service has been removed')
  rescue => e
    Chef::Log.error(e.message)
  end
end

action :register do
  begin
    ipaddress_sync = new_resource.ipaddress_sync
    triggerer_port = new_resource.triggerer_port

    unless node['airflow']['triggerer']['registered']
      query = {}
      query['ID'] = "airflow-triggerer-#{node['hostname']}"
      query['Name'] = 'airflow-triggerer'
      query['Address'] = ipaddress_sync
      query['Port'] = triggerer_port
      json_query = Chef::JSONCompat.to_json(query)

      execute 'Register service in consul' do
        command "curl -X PUT http://localhost:8500/v1/agent/service/register -d '#{json_query}' &>/dev/null"
        action :nothing
      end.run_action(:run)

      node.normal['airflow']['triggerer']['registered'] = true
      Chef::Log.info('Airflow Triggerer service has been registered to consul')
    end
  rescue => e
    Chef::Log.error(e.message)
  end
end

action :deregister do
  begin
    if node['airflow']['triggerer']['registered']
      execute 'Deregister service in consul' do
        command "curl -X PUT http://localhost:8500/v1/agent/service/deregister/airflow-triggerer-#{node['hostname']} &>/dev/null"
        action :nothing
      end.run_action(:run)

      node.normal['airflow']['triggerer']['registered'] = false
      Chef::Log.info('Airflow Triggerer service has been deregistered from consul')
    end
  rescue => e
    Chef::Log.error(e.message)
  end
end
