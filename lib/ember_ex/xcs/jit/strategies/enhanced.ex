defmodule EmberEx.XCS.JIT.Strategies.Enhanced do
  @moduledoc """
  Enhanced JIT compilation strategy combining structural and trace-based approaches.
  
  This hybrid strategy combines the benefits of both structural analysis and
  execution tracing to provide optimal performance for complex operators.
  """
  
  @behaviour EmberEx.XCS.JIT.Strategies.BaseStrategy
  use EmberEx.XCS.JIT.Strategies.JITFallbackMixin
  
  require Logger
  alias EmberEx.XCS.JIT.Cache
  alias EmberEx.XCS.JIT.Strategies.BaseStrategy
  alias EmberEx.XCS.JIT.Strategies.Structural
  alias EmberEx.XCS.JIT.Strategies.Trace
  alias EmberEx.XCS.Graph.EnhancedGraphBuilder
  
  # Define struct first to avoid compilation issues
  defstruct [:structural_strategy, :trace_strategy, :graph_builder]
  
  @doc """
  Initializes a new enhanced strategy.
  
  ## Returns
  
  A new EnhancedStrategy struct
  """
  @type t :: %__MODULE__{
    structural_strategy: Structural.t(),
    trace_strategy: Trace.t(),
    graph_builder: any()
  }

  @spec new() :: t()
  def new do
    %__MODULE__{
      structural_strategy: Structural.new(),
      trace_strategy: Trace.new(),
      graph_builder: EnhancedGraphBuilder.new()
    }
  end
  
  @doc """
  Scores a target to determine how suitable it is for enhanced JIT optimization.
  
  ## Parameters
  
  - strategy: The strategy struct
  - target: Function or operator to analyze
  - options: Optional parameters for scoring
  
  ## Returns
  
  A map with score and rationale where score is a number from 0-100 and
  rationale is a string explaining the score
  """
  @impl EmberEx.XCS.JIT.Strategies.BaseStrategy
  @spec score_target(t(), any(), keyword()) :: %{score: number(), rationale: String.t(), features: map()}
  def score_target(%__MODULE__{} = _strategy, target, _options) do
    features = BaseStrategy.extract_common_features(target)
    
    # Get analyses from both strategies
    structural_analysis = Structural.analyze(target)
    trace_analysis = Trace.analyze(target)
    
    # Enhanced JIT is most valuable when both strategies have value
    structural_score = Map.get(structural_analysis, :score, 0)
    trace_score = Map.get(trace_analysis, :score, 0)
    
    # Boost the score for complex operators that might benefit from both approaches
    complexity_bonus = if structural_score > 20 and trace_score > 10, do: 20, else: 0
    
    # Calculate combined score
    score = div(structural_score + trace_score, 2) + complexity_bonus
    
    rationale_str = Enum.join([
      "Structural score: #{structural_score}",
      "Trace score: #{trace_score}",
      "Combined with complexity bonus: #{complexity_bonus}"
    ], "; ")
    
    %{
      score: score,
      rationale: rationale_str,
      features: features
    }
  end
  
  @doc """
  Compiles a function using enhanced JIT.
  
  ## Parameters
  
  - strategy: The strategy struct
  - target: Function or operator to compile
  - options: Compilation options including:
    - `:sample_input` - Sample input for eager tracing
    - `:force_trace` - Whether to force analysis on every call
    - `:recursive` - Whether to recursively analyze nested operators
    - `:cache` - JIT cache to use
    - `:preserve_stochasticity` - When true, always executes the original function
      to maintain stochastic behavior (important for LLMs)
  
  ## Returns
  
  Compiled function that behaves like the original but with optimizations
  """
  @impl EmberEx.XCS.JIT.Strategies.BaseStrategy
  @spec compile(t(), any(), keyword()) :: function()
  def compile(%__MODULE__{} = _strategy, target, options) do
    # Extract options with default values
    _sample_input = Keyword.get(options, :sample_input) # Not directly used but kept for documentation
    force_trace = Keyword.get(options, :force_trace, false)
    recursive = Keyword.get(options, :recursive, true)
    preserve_stochasticity = Keyword.get(options, :preserve_stochasticity, false)
    _cache_module = BaseStrategy.get_cache(Keyword.get(options, :cache)) # Not directly used but kept for documentation
    
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
        # For enhanced JIT, we use both structure signature and input patterns
        structural_sig = get_structure_signature(target)
        input_sig = compute_input_signature(inputs)
        combined_sig = {structural_sig, input_sig}
        
        # Try to get cached graph
        graph = if force_trace, do: nil, else: Cache.get_with_state(target, combined_sig)
        
        if graph != nil do
          # Execute cached graph
          try do
            EmberEx.XCS.JIT.ExecutionUtils.execute_compiled_graph(graph, inputs, target)
          rescue
            e ->
              Logger.warning("Error executing graph: #{inspect(e)}. Falling back to direct execution.")
              enhanced_compile_and_execute(target, inputs, structural_sig, input_sig, combined_sig, recursive)
          end
        else
          # Build enhanced graph and execute
          enhanced_compile_and_execute(target, inputs, structural_sig, input_sig, combined_sig, recursive)
        end
      end
    end
  end
  
  # Private helper functions
  
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
  
  defp compute_input_signature(inputs) do
    # Compute a stable hash of input structure and values
    :erlang.phash2(inputs)
  end
  
  defp enhanced_compile_and_execute(target, inputs, _structural_sig, _input_sig, combined_sig, recursive) do
    # Record compilation start time for metrics
    compilation_start = :os.system_time(:millisecond) / 1000
    
    # Build enhanced graph using both structural analysis and execution tracing
    {result, graph} = EnhancedGraphBuilder.build_graph(target, inputs, recursive: recursive)
    
    compilation_duration = :os.system_time(:millisecond) / 1000 - compilation_start
    Cache.record_compilation(target, compilation_duration)
    
    # Cache the compiled graph with combined signature
    Cache.set_with_state(target, graph, combined_sig)
    
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
