unified_mode true

# Cookbook:: airflow
# Resource:: config

actions :add, :remove, :register, :deregister
default_action :add

attribute :user, kind_of: String, default: 'airflow'
attribute :group, kind_of: String, default: 'airflow'
attribute :airflow_hosts, kind_of: Array, default: []
attribute :airflow_secrets, kind_of: Hash, default: {}
attribute :cdomain, kind_of: String, default: 'redborder.cluster'

# Airflow configuration attributes
attribute :airflow_dir, kind_of: String, default: '/etc/airflow'
attribute :data_dir, kind_of: String, default: '/var/lib/airflow'
attribute :log_file, kind_of: String, default: '/var/log/airflow/airflow.log'
attribute :pid_file, kind_of: String, default: '/var/run/airflow/airflow.pid'
