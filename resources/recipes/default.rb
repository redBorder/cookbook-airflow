# Cookbook:: airflow
# Recipe:: default
# Copyright:: 2024, redborder
# License:: Affero General Public License, Version 3

airflow_scheduler 'Configure Airflow Scheduler' do
  action :add
end

airflow_webserver 'Configure Airflow Webserver' do
  action :add
end
