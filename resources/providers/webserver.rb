# Cookbook:: airflow
# Provider:: webserver

include Airflow::WebServer

action :add do
  begin
    service 'airflow-webserver' do
      service_name 'airflow-webserver'
      ignore_failure true
      supports status: true, restart: true, enable: true
      action [:enable, :start]
    end

    Chef::Log.info('Airflow Webserver has been processed')
  rescue => e
    Chef::Log.error(e.message)
  end
end

action :remove do
  begin
    service 'airflow-webserver' do
      service_name 'airflow-webserver'
      ignore_failure true
      supports status: true, enable: true
      action [:stop, :disable]
    end

    Chef::Log.info('Airflow Webserver service has been removed')
  rescue => e
    Chef::Log.error(e.message)
  end
end

action :register do
  begin
    ipaddress_mgt = new_resource.ipaddress_mgt
    web_port = new_resource.web_port

    unless node['airflow']['webserver']['registered']
      query = {}
      query['ID'] = "airflow-webserver-#{node['hostname']}"
      query['Name'] = 'airflow-webserver'
      query['Address'] = ipaddress_mgt
      query['Port'] = web_port
      json_query = Chef::JSONCompat.to_json(query)

      execute 'Register service in consul' do
        command "curl -X PUT http://localhost:8500/v1/agent/service/register -d '#{json_query}' &>/dev/null"
        action :nothing
      end.run_action(:run)

      node.normal['airflow']['webserver']['registered'] = true
      Chef::Log.info('Airflow Webserver service has been registered to consul')
    end
  rescue => e
    Chef::Log.error(e.message)
  end
end

action :deregister do
  begin
    if node['airflow']['webserver']['registered']
      execute 'Deregister service in consul' do
        command "curl -X PUT http://localhost:8500/v1/agent/service/deregister/airflow-webserver-#{node['hostname']} &>/dev/null"
        action :nothing
      end.run_action(:run)

      node.normal['airflow']['webserver']['registered'] = false
      Chef::Log.info('Airflow Webserver service has been deregistered from consul')
    end
  rescue => e
    Chef::Log.error(e.message)
  end
end
