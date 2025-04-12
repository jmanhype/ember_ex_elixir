defmodule EmberEx.Metrics.Exporters.Prometheus do
  @moduledoc """
  Prometheus exporter for EmberEx metrics.
  
  This module provides functionality to expose EmberEx metrics in Prometheus format
  for monitoring and visualization. It includes:
  
  1. A Plug-based HTTP endpoint for metrics scraping (/metrics)
  2. Functions to register and record various metric types
  3. Integration with the EmberEx metrics collection system
  """
  
  use Plug.Router
  require Logger

  # Standard plugs for a router
  plug Plug.Logger
  plug :match
  plug :dispatch
  
  @registry :prometheus_ember_registry
  
  @doc """
  Start the Prometheus exporter HTTP server.
  
  ## Parameters
  
  - options: Configuration options
    - port: HTTP port to listen on (default: 9568)
    - address: IP address to bind to (default: 127.0.0.1)
  
  ## Returns
  
  The result of the Plug.Cowboy.http/3 call
  
  ## Examples
  
      iex> EmberEx.Metrics.Exporters.Prometheus.start_link(port: 9000)
      {:ok, #PID<0.123.0>}
  """
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(options \\ []) do
    port = Keyword.get(options, :port, 9568)
    address = Keyword.get(options, :address, {127, 0, 0, 1})
    
    Logger.info("Starting Prometheus metrics exporter on http://#{format_address(address)}:#{port}/metrics")
    Plug.Cowboy.http(__MODULE__, [], port: port, ip: address)
  end

  @doc """
  Set up Prometheus metrics for EmberEx.
  
  This function must be called before using any of the metric recording functions.
  It registers all the counter, gauge, and histogram metrics that will be used.
  
  ## Returns
  
  :ok
  
  ## Examples
  
      iex> EmberEx.Metrics.Exporters.Prometheus.setup_metrics()
      :ok
  """
  @spec setup_metrics() :: :ok
  def setup_metrics do
    Logger.info("Setting up Prometheus metrics")
    
    # Operator metrics
    :prometheus_counter.declare([
      name: :ember_operator_executions_total,
      help: "Total number of operator executions",
      labels: [:operator_type],
      registry: @registry
    ])
    
    :prometheus_histogram.declare([
      name: :ember_operator_execution_time_seconds,
      help: "Time spent executing operators",
      labels: [:operator_type],
      buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10],
      registry: @registry
    ])
    
    # LLM request metrics
    :prometheus_counter.declare([
      name: :ember_llm_requests_total,
      help: "Total number of LLM requests",
      labels: [:model, :provider],
      registry: @registry
    ])
    
    :prometheus_histogram.declare([
      name: :ember_llm_request_time_seconds,
      help: "Time spent in LLM requests",
      labels: [:model, :provider],
      buckets: [0.1, 0.5, 1, 2.5, 5, 10, 15, 30, 60],
      registry: @registry
    ])
    
    :prometheus_counter.declare([
      name: :ember_llm_token_usage_total,
      help: "Total number of tokens used in LLM requests",
      labels: [:model, :provider, :type],
      registry: @registry
    ])
    
    # JIT optimization metrics
    :prometheus_counter.declare([
      name: :ember_jit_optimizations_total,
      help: "Total number of JIT optimizations",
      labels: [:operator_type, :strategy],
      registry: @registry
    ])
    
    :prometheus_histogram.declare([
      name: :ember_jit_optimization_time_seconds,
      help: "Time spent in JIT optimization",
      labels: [:operator_type, :strategy],
      buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10],
      registry: @registry
    ])
    
    :prometheus_gauge.declare([
      name: :ember_jit_cache_size,
      help: "Number of items in the JIT cache",
      registry: @registry
    ])
    
    :prometheus_counter.declare([
      name: :ember_jit_cache_hits_total,
      help: "Total number of JIT cache hits",
      registry: @registry
    ])
    
    :prometheus_counter.declare([
      name: :ember_jit_cache_misses_total,
      help: "Total number of JIT cache misses",
      registry: @registry
    ])
    
    # Memory metrics
    :prometheus_gauge.declare([
      name: :ember_memory_usage_bytes,
      help: "Memory usage by component",
      labels: [:component],
      registry: @registry
    ])
    
    :ok
  end
  
  @doc """
  Record an operator execution.
  
  ## Parameters
  
  - operator_type: The type of operator (e.g., MapOperator, SequenceOperator)
  - execution_time_seconds: The time taken to execute the operator in seconds
  
  ## Returns
  
  :ok
  
  ## Examples
  
      iex> EmberEx.Metrics.Exporters.Prometheus.record_operator_execution("MapOperator", 0.050)
      :ok
  """
  @spec record_operator_execution(String.t(), float()) :: :ok
  def record_operator_execution(operator_type, execution_time_seconds) do
    :prometheus_counter.inc([
      registry: @registry,
      name: :ember_operator_executions_total,
      labels: [operator_type]
    ])
    
    :prometheus_histogram.observe([
      registry: @registry,
      name: :ember_operator_execution_time_seconds,
      labels: [operator_type]
    ], execution_time_seconds)
    
    :ok
  end
  
  @doc """
  Record an LLM request.
  
  ## Parameters
  
  - model: The model used (e.g., "gpt-4", "claude-3")
  - provider: The provider used (e.g., "openai", "anthropic")
  - request_time_seconds: The time taken for the request in seconds
  - prompt_tokens: Number of prompt tokens used
  - completion_tokens: Number of completion tokens used
  
  ## Returns
  
  :ok
  
  ## Examples
  
      iex> EmberEx.Metrics.Exporters.Prometheus.record_llm_request("gpt-4", "openai", 2.5, 100, 50)
      :ok
  """
  @spec record_llm_request(String.t(), String.t(), float(), integer(), integer()) :: :ok
  def record_llm_request(model, provider, request_time_seconds, prompt_tokens, completion_tokens) do
    :prometheus_counter.inc([
      registry: @registry,
      name: :ember_llm_requests_total,
      labels: [model, provider]
    ])
    
    :prometheus_histogram.observe([
      registry: @registry,
      name: :ember_llm_request_time_seconds,
      labels: [model, provider]
    ], request_time_seconds)
    
    :prometheus_counter.inc([
      registry: @registry,
      name: :ember_llm_token_usage_total,
      labels: [model, provider, "prompt"]
    ], prompt_tokens)
    
    :prometheus_counter.inc([
      registry: @registry,
      name: :ember_llm_token_usage_total,
      labels: [model, provider, "completion"]
    ], completion_tokens)
    
    :ok
  end
  
  @doc """
  Record a JIT optimization.
  
  ## Parameters
  
  - operator_type: The type of operator (e.g., MapOperator, SequenceOperator)
  - strategy: The JIT strategy used (e.g., "structural", "trace", "enhanced")
  - optimization_time_seconds: The time taken to optimize in seconds
  
  ## Returns
  
  :ok
  
  ## Examples
  
      iex> EmberEx.Metrics.Exporters.Prometheus.record_jit_optimization("MapOperator", "structural", 0.025)
      :ok
  """
  @spec record_jit_optimization(String.t(), String.t(), float()) :: :ok
  def record_jit_optimization(operator_type, strategy, optimization_time_seconds) do
    :prometheus_counter.inc([
      registry: @registry,
      name: :ember_jit_optimizations_total,
      labels: [operator_type, strategy]
    ])
    
    :prometheus_histogram.observe([
      registry: @registry,
      name: :ember_jit_optimization_time_seconds,
      labels: [operator_type, strategy]
    ], optimization_time_seconds)
    
    :ok
  end
  
  @doc """
  Update JIT cache metrics.
  
  ## Parameters
  
  - cache_size: Current size of the cache
  - hits: Number of new cache hits to record
  - misses: Number of new cache misses to record
  
  ## Returns
  
  :ok
  
  ## Examples
  
      iex> EmberEx.Metrics.Exporters.Prometheus.update_jit_cache_metrics(100, 5, 1)
      :ok
  """
  @spec update_jit_cache_metrics(integer(), integer(), integer()) :: :ok
  def update_jit_cache_metrics(cache_size, hits, misses) do
    :prometheus_gauge.set([
      registry: @registry,
      name: :ember_jit_cache_size
    ], cache_size)
    
    if hits > 0 do
      :prometheus_counter.inc([
        registry: @registry,
        name: :ember_jit_cache_hits_total
      ], hits)
    end
    
    if misses > 0 do
      :prometheus_counter.inc([
        registry: @registry,
        name: :ember_jit_cache_misses_total
      ], misses)
    end
    
    :ok
  end
  
  @doc """
  Update memory usage metrics.
  
  ## Parameters
  
  - component: The component to record memory usage for
  - bytes: The number of bytes used
  
  ## Returns
  
  :ok
  
  ## Examples
  
      iex> EmberEx.Metrics.Exporters.Prometheus.update_memory_usage("jit_cache", 1024000)
      :ok
  """
  @spec update_memory_usage(String.t(), integer()) :: :ok
  def update_memory_usage(component, bytes) do
    :prometheus_gauge.set([
      registry: @registry,
      name: :ember_memory_usage_bytes,
      labels: [component]
    ], bytes)
    
    :ok
  end
  
  # Prometheus metrics endpoint
  get "/metrics" do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, :prometheus_text_format.format(@registry))
  end
  
  # Catch-all route for any other paths
  match _ do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(404, "Not found. Available endpoints: /metrics")
  end
  
  # Helper function to format IP address for logging
  defp format_address({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"
  defp format_address(other), do: inspect(other)
end
