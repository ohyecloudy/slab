defmodule Metrics.Handler do
  use Prometheus.Metric

  def setup() do
    counts = [
      [:slack, :input, :command],
      [:slack, :input, :preview_issue],
      [:slack, :input, :preview_merge_request],
      [:slack, :input, :other]
    ]

    summaries = [
      [:gitlab, :request, :get, :duration]
    ]

    :ok = :telemetry.attach_many(__MODULE__, counts ++ summaries, &handle_event/4, nil)

    Enum.each(counts, fn event_name ->
      Counter.declare(
        name: to_counter_name(event_name),
        help: inspect(event_name)
      )
    end)

    Enum.each(summaries, fn event_name ->
      Summary.declare(
        name: to_milliseconds_name(event_name),
        help: inspect(event_name),
        duration_unit: false
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

  def handle_event(
        [:gitlab, :request, :get, :duration] = event_name,
        %{duration: duration},
        _metadata,
        _config
      ) do
    Summary.observe(
      [name: to_milliseconds_name(event_name)],
      duration
    )
  end

  def handle_event(_, _, _, _), do: nil

  def to_name(event_name) do
    event_name |> Enum.join("_")
  end

  def to_counter_name(event_name) do
    :"#{to_name(event_name)}_total"
  end

  def to_milliseconds_name(event_name) do
    :"#{to_name(event_name)}_milliseconds"
  end
end
