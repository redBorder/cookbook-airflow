# Cookbook:: airflow
# Resource:: triggerer

actions :add, :remove, :register, :deregister
default_action :add

attribute :ipaddress_sync, kind_of: String, default: '127.0.0.1'
attribute :triggerer_port, kind_of: Integer, default: 8794
