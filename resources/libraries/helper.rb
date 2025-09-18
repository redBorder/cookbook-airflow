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
  end
end
