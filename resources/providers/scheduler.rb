# Cookbook:: airflow
# Provider:: scheduler

include Airflow::Scheduler

action :add do
  begin
    service 'airflow-scheduler' do
      service_name 'airflow-scheduler'
      ignore_failure true
      supports status: true, restart: true, enable: true
      action [:enable, :start]
    end

    Chef::Log.info('Airflow Scheduler has been processed')
  rescue => e
    Chef::Log.error(e.message)
  end
end

action :remove do
  begin
    service 'airflow-scheduler' do
      service_name 'airflow-scheduler'
      ignore_failure true
      supports status: true, enable: true
      action [:stop, :disable]
    end

    Chef::Log.info('Airflow Scheduler service has been removed')
  rescue => e
    Chef::Log.error(e.message)
  end
end

action :register do
  begin
    ipaddress_sync = new_resource.ipaddress_sync
    scheduler_port = new_resource.scheduler_port

    unless node['airflow']['scheduler']['registered']
      query = {}
      query['ID'] = "airflow-scheduler-#{node['hostname']}"
      query['Name'] = 'airflow-scheduler'
      query['Address'] = ipaddress_sync
      query['Port'] = scheduler_port
      json_query = Chef::JSONCompat.to_json(query)

      execute 'Register service in consul' do
        command "curl -X PUT http://localhost:8500/v1/agent/service/register -d '#{json_query}' &>/dev/null"
        action :nothing
      end.run_action(:run)

      node.normal['airflow']['scheduler']['registered'] = true
      Chef::Log.info('Airflow Scheduler service has been registered to consul')
    end
  rescue => e
    Chef::Log.error(e.message)
  end
end

action :deregister do
  begin
    if node['airflow']['scheduler']['registered']
      execute 'Deregister service in consul' do
        command "curl -X PUT http://localhost:8500/v1/agent/service/deregister/airflow-scheduler-#{node['hostname']} &>/dev/null"
        action :nothing
      end.run_action(:run)

      node.normal['airflow']['scheduler']['registered'] = false
      Chef::Log.info('Airflow Scheduler service has been deregistered from consul')
    end
  rescue => e
    Chef::Log.error(e.message)
  end
end
