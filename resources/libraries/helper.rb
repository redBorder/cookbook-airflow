module Airflow
  module Helper

    def get_serf_members
      serf_output = `serf members`
      members = {}

      serf_output.each_line do |line|
        parts = line.strip.split
        next unless parts.length >= 2

        hostname = parts[0]
        ip = parts[1].split(':').first
        members[hostname] = ip
      end

      members
    end

    def get_cluster_info(airflow_hosts, this_node)
      serf_members = get_serf_members
      is_cluster = airflow_hosts.length > 1
      master_host = is_cluster ? airflow_hosts.first : nil
      master_ip = master_host ? serf_members[master_host] : nil
      is_master_here = (master_host == this_node)

      {
        is_cluster: is_cluster,
        master_host: master_host,
        master_ip: master_ip,
        is_master_here: is_master_here,
      }
    end

  end
end
