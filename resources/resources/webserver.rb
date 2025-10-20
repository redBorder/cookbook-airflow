# Cookbook:: airflow
# Resource:: webserver

actions :add, :remove, :register, :deregister
default_action :add

attribute :ipaddress_mgt, kind_of: String, default: '127.0.0.1'
attribute :web_port, kind_of: Integer, default: 9191
