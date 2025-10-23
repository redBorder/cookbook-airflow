# Cookbook:: airflow
# Resource:: common

actions :add, :remove
default_action :add

attribute :user, kind_of: String, default: 'airflow'
attribute :group, kind_of: String, default: 'airflow'
attribute :airflow_port, kind_of: Integer, default: 9191
attribute :airflow_secrets, kind_of: Hash, default: {}
attribute :ipaddress_mgt, kind_of: String, default: '127.0.0.1'
attribute :cdomain, kind_of: String, default: 'redborder.cluster'
attribute :api_user, kind_of: String, default: 'admin'
attribute :redis_hosts, kind_of: Array, default: []
attribute :redis_port, kind_of: Integer, default: 26379
attribute :redis_secrets, kind_of: Hash, default: {}
attribute :cpu_cores, kind_of: Integer, default: 4
attribute :ram_memory_kb, kind_of: Integer, default: 16777216
attribute :enables_celery_worker, kind_of: [TrueClass, FalseClass], default: false

# Airflow configuration attributes
attribute :airflow_dir, kind_of: String, default: '/etc/airflow'
attribute :data_dir, kind_of: String, default: '/var/lib/airflow'
attribute :log_file, kind_of: String, default: '/var/log/airflow/airflow.log'
attribute :pid_file, kind_of: String, default: '/var/run/airflow/airflow-scheduler.pid'
attribute :airflow_env_dir, kind_of: String, default: '/opt/airflow'
