defmodule EmberEx.XCS.JIT.Strategies.Structural do
  @moduledoc """
  Structure-based JIT compilation strategy.
  
  Compiles operators by analyzing their structure directly, without execution tracing.
  This approach is particularly effective for container operators with nested sub-operators.
  """
  
  @behaviour EmberEx.XCS.JIT.Strategies.BaseStrategy
  use EmberEx.XCS.JIT.Strategies.JITFallbackMixin
  
  require Logger
  alias EmberEx.XCS.JIT.Cache
  alias EmberEx.XCS.JIT.Strategies.BaseStrategy
  alias EmberEx.XCS.Graph.StructuralGraphBuilder
  
  # Define struct first to avoid compilation issues
  defstruct [:graph_builder]
  
  # Define type for the struct
  @type t :: %__MODULE__{
    graph_builder: any()
  }
  
  @doc """
  Initializes a new structural strategy.
  
  ## Returns
  
  A new StructuralStrategy struct
  """
  @spec new() :: __MODULE__
  def new do
    %__MODULE__{
      graph_builder: StructuralGraphBuilder.new()
    }
  end
  
  @impl BaseStrategy
  @doc """
  Scores a target to determine if structural JIT is appropriate.
  
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
  Analyzes a function to determine if structural JIT is appropriate.
  
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
  Compiles a function using structural JIT.
  
  ## Parameters
  
  - strategy: The strategy struct
  - target: Function or operator to compile
  - options: Compilation options including:
    - `:sample_input` - Optional sample input (not used in structural JIT)
    - `:force_trace` - Whether to force analysis on every call
    - `:recursive` - Whether to recursively analyze nested operators
    - `:cache` - JIT cache to use
    - `:preserve_stochasticity` - When true, always executes the original function
      to maintain stochastic behavior (important for LLMs)
  
  ## Returns
  
  Compiled function that behaves like the original but with optimizations
  """
  @spec compile(__MODULE__.t(), function() | module(), keyword()) :: function()
  def compile(%__MODULE__{}, target, options) do
    force_trace = Keyword.get(options, :force_trace, false)
    recursive = Keyword.get(options, :recursive, true)
    preserve_stochasticity = Keyword.get(options, :preserve_stochasticity, false)
    cache_module = BaseStrategy.get_cache(Keyword.get(options, :cache))
    
    # Create a closure that will handle the JIT compilation and execution
    fn inputs when is_map(inputs) ->
      # Check if we should bypass optimization
      if force_trace or preserve_stochasticity do
        # Execute directly
        execution_start = :os.system_time(:millisecond) / 1000
        result = execute_original(target, inputs)
        execution_duration = :os.system_time(:millisecond) / 1000 - execution_start
        
        Cache.record_execution(target, execution_duration)
        result
      else
        # Try to get structure signature for operators with dynamic state
        state_signature = get_structure_signature(target)
        
        # Try to get cached graph
        graph = Cache.get_with_state(target, state_signature)
        
        if graph != nil do
          # Execute cached graph
          try do
            EmberEx.XCS.JIT.ExecutionUtils.execute_compiled_graph(graph, inputs, target)
          rescue
            e ->
              Logger.warning("Error executing graph: #{inspect(e)}. Falling back to direct execution.")
              build_and_execute_graph(target, inputs, recursive, cache_module, state_signature)
          end
        else
          # Build and execute graph
          build_and_execute_graph(target, inputs, recursive, cache_module, state_signature)
        end
      end
    end
  end
  
  # Private helper functions
  
  defp calculate_score(features, target) do
    score = 0
    rationale = []
    
    # Check if it's an operator module with call/1 function
    {score, rationale} = if features.is_class do
      # Check for operator characteristics
      {score, rationale} = if features.has_forward_method do
        {score + 30, ["Has 'forward' method (likely an operator)" | rationale]}
      else
        {score, rationale}
      end
      
      # Check for nested operators by examining module attributes
      {score, rationale} = has_nested_operators(target, score, rationale)
      
      # Check for operator protocol compliance
      {score, rationale} = if features.has_operator_protocol do
        {score + 20, ["Implements operator protocol" | rationale]}
      else
        {score, rationale}
      end
      
      # Check for specification, which indicates likely optimizer compatibility
      {score, rationale} = if features.has_specification do
        {score + 10, ["Has specification (operator pattern)" | rationale]}
      else
        {score, rationale}
      end
      
      {score, rationale}
    else
      {score, rationale}
    end
    
    {score, rationale}
  end
  
  defp has_nested_operators(target, score, rationale) when is_atom(target) do
    # Look for operator fields in the module attributes
    attrs = target.__info__(:attributes)
    
    if Enum.any?(attrs, fn {key, _} -> 
      is_atom(key) and 
      (to_string(key) =~ ~r/operator/i or to_string(key) =~ ~r/op_/) 
    end) do
      {score + 40, ["Has nested operator fields (container pattern)" | rationale]}
    else
      {score, rationale}
    end
  end
  
  defp has_nested_operators(_target, score, rationale), do: {score, rationale}
  
  defp get_structure_signature(target) when is_atom(target) do
    if function_exported?(target, :get_structure_signature, 0) do
      try do
        target.get_structure_signature()
      rescue
        _ -> nil
      end
    else
      nil
    end
  end
  
  defp get_structure_signature(_), do: nil
  
  defp build_and_execute_graph(target, inputs, recursive, _cache_module, state_signature) do
    # Analyze structure and build graph
    compilation_start = :os.system_time(:millisecond) / 1000
    
    # Build the execution graph using the structural graph builder
    graph_builder = StructuralGraphBuilder.new(recursive: recursive)
    graph = StructuralGraphBuilder.build_graph(graph_builder, target)
    
    compilation_duration = :os.system_time(:millisecond) / 1000 - compilation_start
    Cache.record_compilation(target, compilation_duration)
    
    # Cache compiled graph
    Cache.set_with_state(target, graph, state_signature)
    
    # Execute the graph with fallback
    execute_with_fallback(graph, target, inputs)
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
