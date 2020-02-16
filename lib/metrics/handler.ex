defmodule Metrics.Handler do
  use Prometheus.Metric

  def setup() do
    event_names = [
      [:slack, :input, :command],
      [:slack, :input, :preview_issue],
      [:slack, :input, :preview_merge_request],
      [:slack, :input, :other]
    ]

    :telemetry.attach_many(__MODULE__, event_names, &handle_event/4, nil)

    Enum.each(event_names, fn event_name ->
      Counter.declare(
        name: to_counter_name(event_name),
        help: inspect(event_name)
      )
    end)
  end

  def handle_event([:slack, :input, :command] = event_name, %{count: count}, _metadata, _config) do
    Counter.inc([name: to_counter_name(event_name)], count)
  end

  def handle_event(
        [:slack, :input, :preview_issue] = event_name,
        %{count: count},
        _metadata,
        _config
      ) do
    Counter.inc([name: to_counter_name(event_name)], count)
  end

  def handle_event(
        [:slack, :input, :preview_merge_request] = event_name,
        %{count: count},
        _metadata,
        _config
      ) do
    Counter.inc([name: to_counter_name(event_name)], count)
  end

  def handle_event([:slack, :input, :other] = event_name, %{count: count}, _metadata, _config) do
    Counter.inc([name: to_counter_name(event_name)], count)
  end

  def handle_event(_, _, _, _), do: nil

  def to_counter_name(event_name) do
    name = event_name |> Enum.join("_")
    :"#{name}_total"
  end
end
