defmodule Metrics do
  def start() do
    :prometheus_httpd.start()
  end
end
