defmodule EmberEx.XCS.JIT.Strategies.Trace do
  @moduledoc """
  Execution-trace-based JIT compilation strategy.
  
  Compiles operators by tracing their execution and generating specialized
  execution paths for observed input patterns.
  """
  
  @behaviour EmberEx.XCS.JIT.Strategies.BaseStrategy
  use EmberEx.XCS.JIT.Strategies.JITFallbackMixin
  
  require Logger
  alias EmberEx.XCS.JIT.Cache
  alias EmberEx.XCS.JIT.Strategies.BaseStrategy
  alias EmberEx.XCS.Graph.TraceGraphBuilder
  
  # Define struct first to avoid compilation issues
  defstruct [:graph_builder]
  
  # Define type for the struct
  @type t :: %__MODULE__{
    graph_builder: any()
  }
  
  @doc """
  Initializes a new trace strategy.
  
  ## Returns
  
  A new TraceStrategy struct
  """
  @spec new() :: __MODULE__
  def new do
    %__MODULE__{
      graph_builder: TraceGraphBuilder.new()
    }
  end
  
  @impl BaseStrategy
  @doc """
  Scores a target to determine if trace-based JIT is appropriate.
  
  ## Parameters
  
  - strategy: The strategy struct
  - target: Function or operator to analyze
  - options: Additional options
  
  ## Returns
  
  Map with analysis results, including a score and rationale
  """
  @spec score_target(__MODULE__.t(), function() | module(), keyword()) :: map()
  def score_target(%__MODULE__{}, target, _options) do
    features = BaseStrategy.extract_common_features(target)
    {score, rationale} = calculate_score(features, target)
    
    %{
      score: score,
      rationale: Enum.join(rationale, "; "),
      features: features
    }
  end
  
  @doc """
  Analyzes a function to determine if trace-based JIT is appropriate.
  
  This is kept for backward compatibility, but score_target/3 should be used instead.
  
  ## Parameters
  
  - target: Function or operator to analyze
  
  ## Returns
  
  Map with analysis results, including a score and rationale
  """
  @spec analyze(function() | module()) :: map()
  def analyze(target) do
    score_target(%__MODULE__{}, target, [])
  end
  
  @impl BaseStrategy
  @doc """
  Compiles a function using trace-based JIT.
  
  ## Parameters
  
  - strategy: The strategy struct
  - target: Function or operator to compile
  - options: Compilation options including:
    - `:sample_input` - Sample input for eager tracing
    - `:force_trace` - Whether to force trace on every call
    - `:recursive` - Whether to recursively analyze nested operators
    - `:cache` - JIT cache to use
    - `:preserve_stochasticity` - When true, always executes the original function
      to maintain stochastic behavior (important for LLMs)
  
  ## Returns
  
  Compiled function that behaves like the original but with optimizations
  """
  @spec compile(__MODULE__.t(), function() | module(), keyword()) :: function()
  def compile(%__MODULE__{}, target, options) do
    _sample_input = Keyword.get(options, :sample_input)
    force_trace = Keyword.get(options, :force_trace, false)
    preserve_stochasticity = Keyword.get(options, :preserve_stochasticity, false)
    _cache_module = BaseStrategy.get_cache(Keyword.get(options, :cache))
    
    # Create a closure that will handle the JIT compilation and execution
    fn inputs when is_map(inputs) ->
      # Check if we should bypass optimization
      if preserve_stochasticity do
        # Always execute directly for stochastic functions
        execution_start = :os.system_time(:millisecond) / 1000
        result = execute_original(target, inputs)
        execution_duration = :os.system_time(:millisecond) / 1000 - execution_start
        
        Cache.record_execution(target, execution_duration)
        result
      else
        # For trace-based JIT, we use the input signature as the cache key
        input_signature = compute_input_signature(inputs)
        
        # Try to get cached graph for this input pattern
        graph = if force_trace, do: nil, else: Cache.get_with_state(target, input_signature)
        
        if graph != nil do
          # Execute cached graph
          try do
            EmberEx.XCS.JIT.ExecutionUtils.execute_compiled_graph(graph, inputs, target)
          rescue
            e ->
              Logger.warning("Error executing graph: #{inspect(e)}. Falling back to direct execution.")
              trace_and_execute(target, inputs, input_signature)
          end
        else
          # Trace execution and build graph
          trace_and_execute(target, inputs, input_signature)
        end
      end
    end
  end
  
  # Private helper functions
  
  defp calculate_score(features, _target) do
    score = 0
    rationale = []
    
    # Trace-based JIT works well for simple functions
    {score, rationale} = if features.is_function do
      {score + 30, ["Simple function (good for tracing)" | rationale]}
    else
      {score, rationale}
    end
    
    # Trace-based JIT is less effective for operators with complex nested structure
    {score, rationale} = if features.has_forward_method do
      {score + 10, ["Has 'forward' method" | rationale]}
    else
      {score, rationale}
    end
    
    # Trace-based JIT doesn't work well with highly branching control flow
    # We can't easily detect this in Elixir, but we can score other things
    
    {score, rationale}
  end
  
  defp compute_input_signature(inputs) do
    # Compute a stable hash of input structure and values
    :erlang.phash2(inputs)
  end
  
  defp trace_and_execute(target, inputs, input_signature) do
    # Record execution start time for metrics
    compilation_start = :os.system_time(:millisecond) / 1000
    
    # Execute the target while tracing the execution
    {result, trace} = TraceGraphBuilder.trace_execution(target, inputs)
    
    # Build graph from the execution trace
    graph = TraceGraphBuilder.build_graph_from_trace(trace)
    
    compilation_duration = :os.system_time(:millisecond) / 1000 - compilation_start
    Cache.record_compilation(target, compilation_duration)
    
    # Cache the compiled graph with input signature
    Cache.set_with_state(target, graph, input_signature)
    
    # Return the execution result
    result
  end
  
  defp execute_original(target, inputs) when is_atom(target) do
    # Handle module-based operators
    target.call(inputs)
  end
  
  defp execute_original(target, inputs) when is_function(target) do
    # Handle function operators
    target.(inputs)
  end
end
