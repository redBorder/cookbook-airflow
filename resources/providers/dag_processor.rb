# Cookbook:: airflow
# Provider:: dag_proccessor

include Airflow::DagProccessor

action :add do
  begin
    service 'airflow-dag-processor' do
      service_name 'airflow-dag-processor'
      ignore_failure true
      supports status: true, restart: true, enable: true
      action [:enable, :start]
    end

    Chef::Log.info('Airflow Dag Proccessor has been processed')
  rescue => e
    Chef::Log.error(e.message)
  end
end

action :remove do
  begin
    service 'airflow-dag-processor' do
      service_name 'airflow-dag-processor'
      ignore_failure true
      supports status: true, enable: true
      action [:stop, :disable]
    end

    Chef::Log.info('Airflow Dag Proccessor service has been removed')
  rescue => e
    Chef::Log.error(e.message)
  end
end

action :register do
  begin
    ipaddress_sync = new_resource.ipaddress_sync
    dag_processor_port = new_resource.dag_processor_port

    unless node['airflow']['dag-processor']['registered']
      query = {}
      query['ID'] = "airflow-dag-processor-#{node['hostname']}"
      query['Name'] = 'airflow-dag-processor'
      query['Address'] = ipaddress_sync
      query['Port'] = dag_processor_port
      json_query = Chef::JSONCompat.to_json(query)

      execute 'Register service in consul' do
        command "curl -X PUT http://localhost:8500/v1/agent/service/register -d '#{json_query}' &>/dev/null"
        action :nothing
      end.run_action(:run)

      node.normal['airflow']['dag-processor']['registered'] = true
      Chef::Log.info('Airflow Dag Proccessor service has been registered to consul')
    end
  rescue => e
    Chef::Log.error(e.message)
  end
end

action :deregister do
  begin
    if node['airflow']['dag-processor']['registered']
      execute 'Deregister service in consul' do
        command "curl -X PUT http://localhost:8500/v1/agent/service/deregister/airflow-dag-processor-#{node['hostname']} &>/dev/null"
        action :nothing
      end.run_action(:run)

      node.normal['airflow']['dag-processor']['registered'] = false
      Chef::Log.info('Airflow Dag Proccessor service has been deregistered from consul')
    end
  rescue => e
    Chef::Log.error(e.message)
  end
end
