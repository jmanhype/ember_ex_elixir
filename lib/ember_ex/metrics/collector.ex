defmodule EmberEx.Metrics.Collector do
  @moduledoc """
  Metrics collection system for EmberEx.
  
  This module provides functionality for recording, aggregating, and retrieving metrics
  about EmberEx operations, with a focus on performance monitoring, debugging, and
  optimization.
  """
  
  require Logger
  
  @typedoc "Metric type, representing different categories of measurements"
  @type metric_type :: :latency | :count | :gauge | :distribution
  
  @typedoc "Metric name, used as an identifier"
  @type metric_name :: String.t()
  
  @typedoc "Metric value, typically a number"
  @type metric_value :: number()
  
  @typedoc "Metric tags, used for categorization and filtering"
  @type metric_tags :: %{optional(String.t()) => String.t()}
  
  @typedoc "Metric data structure"
  @type metric :: %{
    name: metric_name(),
    value: metric_value(),
    type: metric_type(),
    tags: metric_tags(),
    timestamp: integer()
  }
  
  @doc """
  Record a metric with the given name, value, type, and tags.
  
  ## Parameters
  
  - name: The name of the metric
  - value: The value of the metric
  - type: The type of the metric
  - tags: Additional tags to associate with the metric
  
  ## Returns
  
  `:ok`
  
  ## Examples
  
      iex> EmberEx.Metrics.Collector.record("operator.execution_time", 123.45, :latency, %{"operator" => "llm"})
      :ok
  """
  @spec record(metric_name(), metric_value(), metric_type(), metric_tags()) :: :ok
  def record(name, value, type, tags \\ %{}) do
    metric = %{
      name: name,
      value: value,
      type: type,
      tags: tags,
      timestamp: System.system_time(:millisecond)
    }
    
    # Store the metric
    store_metric(metric)
    
    # Log the metric for debugging purposes
    Logger.debug("Recorded metric: #{inspect(metric)}")
    
    :ok
  end
  
  @doc """
  Record the execution time of a function and store it as a latency metric.
  
  ## Parameters
  
  - name: The name of the metric
  - tags: Additional tags to associate with the metric
  - function: The function to execute and measure
  
  ## Returns
  
  The result of the function
  
  ## Examples
  
      iex> EmberEx.Metrics.Collector.time("operator.execution_time", %{"operator" => "llm"}, fn -> :timer.sleep(100); :ok end)
      :ok
  """
  @spec time(metric_name(), metric_tags(), (-> any())) :: any()
  def time(name, tags \\ %{}, function) when is_function(function, 0) do
    start_time = System.monotonic_time(:microsecond)
    result = function.()
    end_time = System.monotonic_time(:microsecond)
    
    # Calculate duration in milliseconds
    duration_ms = (end_time - start_time) / 1000.0
    
    # Record the latency metric
    record(name, duration_ms, :latency, tags)
    
    result
  end
  
  @doc """
  Increment a counter metric.
  
  ## Parameters
  
  - name: The name of the metric
  - amount: The amount to increment by (default: 1)
  - tags: Additional tags to associate with the metric
  
  ## Returns
  
  `:ok`
  
  ## Examples
  
      iex> EmberEx.Metrics.Collector.increment("operator.execution_count", 1, %{"operator" => "llm"})
      :ok
  """
  @spec increment(metric_name(), number(), metric_tags()) :: :ok
  def increment(name, amount \\ 1, tags \\ %{}) do
    record(name, amount, :count, tags)
  end
  
  @doc """
  Record a gauge metric.
  
  ## Parameters
  
  - name: The name of the metric
  - value: The value of the metric
  - tags: Additional tags to associate with the metric
  
  ## Returns
  
  `:ok`
  
  ## Examples
  
      iex> EmberEx.Metrics.Collector.gauge("operator.memory_usage", 1024, %{"operator" => "llm"})
      :ok
  """
  @spec gauge(metric_name(), number(), metric_tags()) :: :ok
  def gauge(name, value, tags \\ %{}) do
    record(name, value, :gauge, tags)
  end
  
  @doc """
  Get metrics matching the given filter.
  
  ## Parameters
  
  - filter: A function that takes a metric and returns true if it should be included
  
  ## Returns
  
  A list of metrics matching the filter
  
  ## Examples
  
      iex> EmberEx.Metrics.Collector.get_metrics(fn metric -> metric.name == "operator.execution_time" end)
      [%{name: "operator.execution_time", value: 123.45, type: :latency, tags: %{"operator" => "llm"}, timestamp: 1617123456789}]
  """
  @spec get_metrics((metric() -> boolean())) :: [metric()]
  def get_metrics(filter \\ fn _ -> true end) do
    # Get metrics from storage
    metrics_from_storage()
    |> Enum.filter(filter)
  end
  
  @doc """
  Clear all stored metrics.
  
  ## Returns
  
  `:ok`
  
  ## Examples
  
      iex> EmberEx.Metrics.Collector.clear()
      :ok
  """
  @spec clear() :: :ok
  def clear do
    EmberEx.Metrics.Storage.clear()
  end
  
  # Private functions
  
  defp store_metric(metric) do
    EmberEx.Metrics.Storage.store(metric)
  end
  
  defp metrics_from_storage do
    EmberEx.Metrics.Storage.get_all()
  end
end
