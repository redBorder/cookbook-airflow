# Cookbook:: airflow
# Resource:: scheduler

actions :add, :remove, :register, :deregister
default_action :add

attribute :ipaddress_sync, kind_of: String, default: '127.0.0.1'
attribute :scheduler_port, kind_of: Integer, default: 8793
