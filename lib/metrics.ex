defmodule Metrics do
  require Prometheus.Registry

  def start() do
    :prometheus_httpd.start()
    Prometheus.Registry.register_collector(:prometheus_process_collector)
  end
end
