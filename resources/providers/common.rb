# Cookbook:: airflow
# Provider:: common

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
    airflow_scheduler_hosts = new_resource.airflow_scheduler_hosts
    airflow_webserver_hosts = new_resource.airflow_webserver_hosts
    redis_hosts = new_resource.redis_hosts
    redis_port = new_resource.redis_port
    cpu_cores = new_resource.cpu_cores
    ram_memory_kb = new_resource.ram_memory_kb
    is_celery_worker_required = enables_celery_worker?(airflow_scheduler_hosts, airflow_webserver_hosts)
    workers = airflow_workers(cpu_cores, ram_memory_kb)

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
        redis_hosts: redis_hosts,
        redis_port: redis_port,
        celery_worker_concurrency: workers[:celery_worker_concurrency],
        webserver_workers: workers[:webserver_workers],
        is_celery_worker_required: is_celery_worker_required
      )
    end

    template "#{data_dir}/jwt_secret" do
      source 'jwt_secret.erb'
      owner user
      group group
      mode '0644'
      cookbook 'airflow'
      variables(airflow_password: airflow_password)
    end

    template "#{airflow_env_dir}/simple_auth_manager_passwords.json" do
      source 'simple_auth_manager_passwords.json.conf.erb'
      owner user
      group group
      mode '0644'
      cookbook 'airflow'
      variables(
        api_user: api_user,
        airflow_password: airflow_password
      )
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

    if is_celery_worker_required
      service 'airflow-celery-worker' do
        service_name 'airflow-celery-worker'
        ignore_failure true
        supports status: true, restart: true, enable: true
        action [:start, :enable]
      end
    else
      service 'airflow-celery-worker' do
        service_name 'airflow-celery-worker'
        ignore_failure true
        supports status: true, enable: true
        action [:stop, :disable]
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
