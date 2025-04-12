defmodule EmberEx.XCS.JIT.Cache do
  @moduledoc """
  Caching system for JIT-compiled functions and operators.
  
  Provides memory caching of compiled execution graphs and metrics tracking
  to optimize repeated executions and allow for performance analysis.
  """
  
  use GenServer
  require Logger
  
  @type metrics_t :: %{
    compilation_count: non_neg_integer(),
    execution_count: non_neg_integer(),
    cache_hit_count: non_neg_integer(),
    compilation_time: float(),
    execution_time: float()
  }
  
  @type t :: %__MODULE__{
    cache_entries: map(),
    state_signatures: map(),
    metrics: map()
  }
  
  defstruct cache_entries: %{},
            state_signatures: %{},
            metrics: %{
              global: %{
                compilation_count: 0,
                execution_count: 0,
                cache_hit_count: 0,
                compilation_time: 0.0,
                execution_time: 0.0
              }
            }
            
  @doc """
  Starts the JIT cache server.
  
  ## Returns
  
  `{:ok, pid}` if the server was started successfully, `{:error, reason}` otherwise
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Initializes the JIT cache.
  
  ## Parameters
  
  - opts: Initialization options (currently unused)
  
  ## Returns
  
  `{:ok, state}` with the initial state
  """
  @spec init(keyword()) :: {:ok, t()}
  def init(_opts) do
    Logger.info("Started JIT Cache")
    {:ok, %__MODULE__{}}
  end
  
  @doc """
  Gets a compiled graph for a function using its state signature.
  
  ## Parameters
  
  - target: Target function or operator
  - state_signature: Optional state signature for dynamic state tracking
  
  ## Returns
  
  The compiled graph if found in cache, nil otherwise
  """
  @spec get_with_state(function() | module(), term() | nil) :: term() | nil
  def get_with_state(target, state_signature \\ nil) do
    GenServer.call(__MODULE__, {:get_with_state, target, state_signature})
  end
  
  @doc """
  Sets a compiled graph for a function with optional state signature.
  
  ## Parameters
  
  - target: Target function or operator
  - graph: Compiled execution graph
  - state_signature: Optional state signature for dynamic state tracking
  
  ## Returns
  
  `:ok`
  """
  @spec set_with_state(function() | module(), term(), term() | nil) :: :ok
  def set_with_state(target, graph, state_signature \\ nil) do
    GenServer.call(__MODULE__, {:set_with_state, target, graph, state_signature})
  end
  
  @doc """
  Records compilation metrics for a function.
  
  ## Parameters
  
  - target: Target function or operator
  - duration: Compilation time in seconds
  
  ## Returns
  
  `:ok`
  """
  @spec record_compilation(function() | module(), float()) :: :ok
  def record_compilation(target, duration) do
    GenServer.cast(__MODULE__, {:record_compilation, target, duration})
  end
  
  @doc """
  Records execution metrics for a function.
  
  ## Parameters
  
  - target: Target function or operator
  - duration: Execution time in seconds
  
  ## Returns
  
  `:ok`
  """
  @spec record_execution(function() | module(), float()) :: :ok
  def record_execution(target, duration) do
    GenServer.cast(__MODULE__, {:record_execution, target, duration})
  end
  
  @doc """
  Records cache hit metrics for a function.
  
  ## Parameters
  
  - target: Target function or operator
  
  ## Returns
  
  `:ok`
  """
  @spec record_cache_hit(function() | module()) :: :ok
  def record_cache_hit(target) do
    GenServer.cast(__MODULE__, {:record_cache_hit, target})
  end
  
  @doc """
  Gets metrics for a specific function or global metrics.
  
  ## Parameters
  
  - target: Optional target function or operator (nil for global metrics)
  
  ## Returns
  
  Metrics map
  """
  @spec get_metrics(function() | module() | nil) :: metrics_t()
  def get_metrics(target \\ nil) do
    GenServer.call(__MODULE__, {:get_metrics, target})
  end
  
  @doc """
  Clears the cache.
  
  ## Returns
  
  `:ok`
  """
  @spec clear() :: :ok
  def clear do
    GenServer.call(__MODULE__, :clear)
  end
  
  @doc """
  Gets statistics about cache usage.
  
  ## Returns
  
  A map containing cache statistics
  """
  @spec get_stats() :: %{hits: non_neg_integer(), misses: non_neg_integer(), hit_rate: float(), total_calls: non_neg_integer()}
  def get_stats do
    metrics = get_metrics()
    hits = metrics.cache_hit_count || 0
    total_executions = metrics.execution_count || 0
    misses = max(0, total_executions - hits)
    
    hit_rate = case total_executions do
      0 -> 0.0
      _ -> min(100.0, (hits / total_executions) * 100.0)
    end
    
    %{
      hits: hits,
      misses: misses,
      hit_rate: hit_rate,
      total_calls: total_executions
    }
  end
  
  # GenServer callbacks
  
  def handle_call({:get_with_state, target, state_signature}, _from, state) do
    key = get_cache_key(target, state_signature)
    
    case Map.get(state.cache_entries, key) do
      nil -> {:reply, nil, state}
      graph -> 
        GenServer.cast(__MODULE__, {:record_cache_hit, target})
        {:reply, graph, state}
    end
  end
  
  def handle_call({:set_with_state, target, graph, state_signature}, _from, state) do
    key = get_cache_key(target, state_signature)
    
    # Store graph in cache
    cache_entries = Map.put(state.cache_entries, key, graph)
    
    # Store state signature mapping
    state_signatures = case state_signature do
      nil -> state.state_signatures
      _ -> 
        target_key = get_target_key(target)
        sig_map = Map.get(state.state_signatures, target_key, %{})
        sig_map = Map.put(sig_map, state_signature, key)
        Map.put(state.state_signatures, target_key, sig_map)
    end
    
    {:reply, :ok, %{state | cache_entries: cache_entries, state_signatures: state_signatures}}
  end
  
  def handle_call({:get_metrics, target}, _from, state) do
    metrics = case target do
      nil -> Map.get(state.metrics, :global)
      _ -> 
        target_key = get_target_key(target)
        Map.get(state.metrics, target_key, %{
          compilation_count: 0,
          execution_count: 0,
          cache_hit_count: 0,
          compilation_time: 0.0,
          execution_time: 0.0
        })
    end
    
    {:reply, metrics, state}
  end
  
  def handle_call(:clear, _from, state) do
    {:reply, :ok, %{state | 
      cache_entries: %{}, 
      state_signatures: %{},
      metrics: %{global: Map.get(state.metrics, :global, %{
        compilation_count: 0,
        execution_count: 0,
        cache_hit_count: 0,
        compilation_time: 0.0,
        execution_time: 0.0
      })}
    }}
  end
  
  def handle_cast({:record_compilation, target, duration}, state) do
    # Update global metrics
    global_metrics = Map.get(state.metrics, :global)
    global_metrics = %{
      global_metrics |
      compilation_count: (global_metrics.compilation_count || 0) + 1,
      compilation_time: (global_metrics.compilation_time || 0.0) + duration
    }
    
    # Update target-specific metrics
    target_key = get_target_key(target)
    target_metrics = Map.get(state.metrics, target_key, %{
      compilation_count: 0,
      execution_count: 0,
      cache_hit_count: 0,
      compilation_time: 0.0,
      execution_time: 0.0
    })
    
    target_metrics = %{
      target_metrics |
      compilation_count: target_metrics.compilation_count + 1,
      compilation_time: target_metrics.compilation_time + duration
    }
    
    metrics = state.metrics
      |> Map.put(:global, global_metrics)
      |> Map.put(target_key, target_metrics)
    
    {:noreply, %{state | metrics: metrics}}
  end
  
  def handle_cast({:record_execution, target, duration}, state) do
    # Update global metrics
    global_metrics = Map.get(state.metrics, :global)
    global_metrics = %{
      global_metrics |
      execution_count: (global_metrics.execution_count || 0) + 1,
      execution_time: (global_metrics.execution_time || 0.0) + duration
    }
    
    # Update target-specific metrics
    target_key = get_target_key(target)
    target_metrics = Map.get(state.metrics, target_key, %{
      compilation_count: 0,
      execution_count: 0,
      cache_hit_count: 0,
      compilation_time: 0.0,
      execution_time: 0.0
    })
    
    target_metrics = %{
      target_metrics |
      execution_count: target_metrics.execution_count + 1,
      execution_time: target_metrics.execution_time + duration
    }
    
    metrics = state.metrics
      |> Map.put(:global, global_metrics)
      |> Map.put(target_key, target_metrics)
    
    {:noreply, %{state | metrics: metrics}}
  end
  
  def handle_cast({:record_cache_hit, target}, state) do
    # Update global metrics
    global_metrics = Map.get(state.metrics, :global)
    global_metrics = %{
      global_metrics |
      cache_hit_count: (global_metrics.cache_hit_count || 0) + 1
    }
    
    # Update target-specific metrics
    target_key = get_target_key(target)
    target_metrics = Map.get(state.metrics, target_key, %{
      compilation_count: 0,
      execution_count: 0,
      cache_hit_count: 0,
      compilation_time: 0.0,
      execution_time: 0.0
    })
    
    target_metrics = %{
      target_metrics |
      cache_hit_count: target_metrics.cache_hit_count + 1
    }
    
    metrics = state.metrics
      |> Map.put(:global, global_metrics)
      |> Map.put(target_key, target_metrics)
    
    {:noreply, %{state | metrics: metrics}}
  end
  
  # Helper functions
  
  defp get_cache_key(target, state_signature) do
    target_key = get_target_key(target)
    
    case state_signature do
      nil -> target_key
      _ -> {target_key, state_signature}
    end
  end
  
  defp get_target_key(target) do
    cond do
      is_function(target) -> 
        # Use function identity as key
        :erlang.fun_info(target)[:unique_integer]
      is_atom(target) -> 
        # Use module name for module targets
        target
      true -> 
        # Convert other targets to a stable identifier
        :erlang.phash2(target)
    end
  end
end
