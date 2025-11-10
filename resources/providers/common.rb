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
    airflow_dags_folder = new_resource.airflow_dags_folder
    airflow_venv_bin = new_resource.airflow_venv_bin
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
    redis_hosts = new_resource.redis_hosts
    redis_port = new_resource.redis_port
    redis_secrets = new_resource.redis_secrets
    redis_password = redis_secrets['pass'] unless redis_secrets.empty?
    logstash_hosts = new_resource.logstash_hosts
    cpu_cores = new_resource.cpu_cores
    ram_memory_kb = new_resource.ram_memory_kb
    workers = airflow_workers(cpu_cores, ram_memory_kb)
    enables_celery_worker = new_resource.enables_celery_worker
    s3_malware_user = new_resource.malware_access_key
    s3_malware_password = new_resource.malware_secret_key
    secret_key = airflow_secrets['pass'] unless airflow_secrets.empty?

    dnf_package ['redborder-malware-pythonpyenv', 'airflow'] do
      action :upgrade
    end

    execute 'create_user' do
      command "/usr/sbin/useradd -r #{user} -s /sbin/nologin"
      ignore_failure true
      not_if "getent passwd #{user}"
    end

    execute 'add_airflow_to_malware_group' do
      command "usermod -aG malware #{user}"
      only_if 'getent group malware'
      not_if "id -nG #{user} | grep -qw malware"
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
        airflow_dags_folder: airflow_dags_folder,
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
        redis_password: redis_password,
        secret_key: secret_key,
        celery_worker_concurrency: workers[:celery_worker_concurrency],
        webserver_workers: workers[:webserver_workers],
        enables_celery_worker: enables_celery_worker
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

    template "#{airflow_dir}/logstash_hosts.yml" do
      source 'logstash_hosts.yml.erb'
      owner user
      group group
      mode '0644'
      cookbook 'airflow'
      variables(
        logstash_hosts: logstash_hosts
      )
    end

    link "#{data_dir}/airflow.cfg" do
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
      command "#{airflow_venv_bin} db migrate"
      user user
      group group
      environment(
        'AIRFLOW_HOME' => data_dir
      )
      not_if { ::File.exist?("#{data_dir}/airflow.db_initialized") }
      notifies :create_if_missing, "file[#{data_dir}/airflow.db_initialized]", :immediately
    end

    # Connection with MinIO
    minio_conn_id = 'minio_conn'
    minio_endpoint = "http://s3.service.#{cdomain}:9001"
    minio_access_key = s3_malware_user
    minio_secret_key = s3_malware_password

    execute 'add_minio_s3_connection' do
      command <<-EOC
        #{airflow_venv_bin} connections add #{minio_conn_id} \
          --conn-type 'aws' \
          --conn-login '#{minio_access_key}' \
          --conn-password '#{minio_secret_key}' \
          --conn-extra '{"host": "#{minio_endpoint}", "aws_access_key_id": "#{minio_access_key}", "aws_secret_access_key": "#{minio_secret_key}", "endpoint_url": "#{minio_endpoint}", "region_name": "us-east-1"}'
      EOC
      user user
      group group
      environment(
        'AIRFLOW_HOME' => data_dir
      )

      # Only execute if the connection does NOT yet exist.
      # The ‘connections get’ command will return an error if the connection does not exist.
      not_if "#{airflow_venv_bin} connections list --output json | grep -w '\"conn_id\": \"#{minio_conn_id}\"'",
       user: user,
       environment: { 'AIRFLOW_HOME' => data_dir }
    end

    directory airflow_dags_folder do
      owner user
      group group
      mode '0755'
      recursive true
      action :create
    end

    remote_directory airflow_dags_folder do
      source 'dags'
      owner user
      group group
      mode '0755'
      files_mode '0644'
      cookbook 'airflow'
      action :create
    end

    if enables_celery_worker
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
