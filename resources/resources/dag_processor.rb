# Cookbook:: airflow
# Resource:: dag_proccessor

actions :add, :remove, :register, :deregister
default_action :add

attribute :ipaddress_sync, kind_of: String, default: '127.0.0.1'
attribute :dag_processor_port, kind_of: Integer, default: 8795
