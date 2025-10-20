module Airflow
  module Helper
    # Generates or ensures a secure value in a file.
    # - provided: if you pass it, it returns it directly.
    # - path: file where the value is saved/read.
    # - length: length in hexadecimal characters (e.g., 32 = 16 bytes).
    def ensure_value(path, length: 32)
      if ::File.exist?(path)
        ::File.read(path).strip
      else
        value = SecureRandom.hex(length / 2)
        FileUtils.mkdir_p(::File.dirname(path))
        ::File.write(path, value)
        value
      end
    end

    # Returns true if a Celery worker is required.
    # Celery is needed when scheduler and webserver are NOT on the same node.
    #
    # @param scheduler_hosts [Array<String>] list of nodes running the scheduler
    # @param webserver_hosts [Array<String>] list of nodes running the webserver
    # @return [Boolean] true if celery worker is required
    def enables_celery_worker?(scheduler_hosts, webserver_hosts)
      return false if scheduler_hosts.nil? || webserver_hosts.nil?

      all_hosts = (scheduler_hosts + webserver_hosts).uniq
      all_hosts.size > 1
    end

    # Calculates optimal number of workers for Celery and Airflow webserver based on node resources.
    #
    # @param cpu_cores [Integer] number of CPU cores on the node
    # @param ram_memory_kb [Integer] total RAM in KB
    # @return [Hash] containing :celery_worker_concurrency and :webserver_workers
    def airflow_workers(cpu_cores, ram_memory_kb)
      # Convert memory from KB to GB
      memory_gb = ram_memory_kb.to_f / 1024 / 1024

      # Celery Worker Concurrency
      celery_concurrency = [cpu_cores, (cpu_cores * 2)].min

      # Limit by available memory (~2GB per worker)
      max_celery_by_mem = (memory_gb / 2).floor
      celery_concurrency = [celery_concurrency, max_celery_by_mem].min
      celery_concurrency = 1 if celery_concurrency < 1

      # Webserver Workers
      webserver_workers = (2 * cpu_cores) + 1

      # Limit by available memory (~0.5GB per worker)
      max_webserver_by_mem = (memory_gb / 0.5).floor
      webserver_workers = [webserver_workers, max_webserver_by_mem].min
      webserver_workers = 1 if webserver_workers < 1

      {
        celery_worker_concurrency: celery_concurrency,
        webserver_workers: webserver_workers,
      }
    end
  end
end
