defmodule EmberEx.XCS.JIT.Core do
  @moduledoc """
  Core JIT compilation system for EmberEx XCS.
  
  Provides a unified Just-In-Time compilation mechanism that optimizes operators
  and functions by analyzing their structure and execution patterns.
  """
  
  require Logger
  alias EmberEx.XCS.JIT.Cache
  alias EmberEx.XCS.JIT.Modes
  alias EmberEx.XCS.JIT.StrategySelector
  
  @doc """
  Settings for JIT compilation behavior.
  
  Encapsulates all configuration options for the JIT system.
  """
  defmodule Settings do
    @moduledoc """
    Settings for JIT compilation behavior.
    
    Encapsulates all configuration options for the JIT system.
    """
    
    @type t :: %__MODULE__{
      mode: Modes.t(),
      force_trace: boolean(),
      sample_input: map() | nil,
      custom_cache: module() | nil,
      recursive: boolean(),
      preserve_stochasticity: boolean(),
      options: keyword()
    }
    
    defstruct [
      mode: :auto,
      force_trace: false,
      sample_input: nil,
      custom_cache: nil,
      recursive: true,
      preserve_stochasticity: false,
      options: []
    ]
    
    @doc """
    Creates a new settings struct with normalized options.
    
    ## Parameters
    
    - opts: Keyword list of options
    
    ## Returns
    
    A new Settings struct
    """
    @spec new(keyword()) :: t()
    def new(opts \\ []) do
      # Extract known options
      mode = Keyword.get(opts, :mode, :auto)
      force_trace = Keyword.get(opts, :force_trace, false)
      sample_input = Keyword.get(opts, :sample_input, nil)
      custom_cache = Keyword.get(opts, :cache, nil)
      recursive = Keyword.get(opts, :recursive, true)
      preserve_stochasticity = Keyword.get(opts, :preserve_stochasticity, false)
      
      # Extract any remaining options for strategy-specific settings
      known_keys = [:mode, :force_trace, :sample_input, :cache, :recursive, :preserve_stochasticity]
      options = Keyword.drop(opts, known_keys)
      
      # Normalize mode
      mode = if is_binary(mode) do
        Modes.from_string(mode)
      else
        mode
      end
      
      %__MODULE__{
        mode: mode,
        force_trace: force_trace,
        sample_input: sample_input,
        custom_cache: custom_cache,
        recursive: recursive,
        preserve_stochasticity: preserve_stochasticity,
        options: options
      }
    end
  end
  
  # Global strategy selector
  @selector StrategySelector.new()

  @doc """
  Optimizes functions and operators with Just-In-Time compilation.
  
  Core optimization function that analyzes and compiles functions or
  operator modules for efficient execution. Supports multiple compilation
  strategies with automatic selection based on target characteristics.
  
  ## Parameters
  
  - target: Target function or operator module
  - opts: Compilation options including:
    - `:mode` - Compilation strategy to use (auto, trace, structural, enhanced)
    - `:force_trace` - Whether to force retracing on each call
    - `:sample_input` - Example input for eager compilation
    - `:cache` - Custom cache implementation
    - `:recursive` - Whether to recursively optimize nested functions
    - `:preserve_stochasticity` - If true, always executes the original function even
      when inputs match previous calls. This is important for LLMs where
      multiple calls with the same prompts should produce different outputs.
  
  ## Returns
  
  Optimized function or operator module
  
  ## Examples
  
  ```elixir
  # Simple usage
  optimized_operator = EmberEx.XCS.JIT.Core.jit(MyOperator)
  
  # Advanced configuration
  optimized_func = EmberEx.XCS.JIT.Core.jit(
    &process_data/1,
    mode: :structural,
    sample_input: %{data: "example"},
    recursive: false
  )
  
  # LLM usage, preserving stochasticity
  llm_op = EmberEx.XCS.JIT.Core.jit(
    LLMOperator,
    preserve_stochasticity: true
  )
  ```
  """
  @spec jit(function() | module(), keyword()) :: function() | module()
  def jit(target, opts \\ []) do
    # Prepare optimization configuration
    settings = Settings.new(opts)
    
    # Get optimal compilation strategy
    {strategy_module, strategy} = StrategySelector.select_strategy(@selector, target, settings.mode)
    
    # Apply appropriate optimization based on target type
    apply_optimization(target, strategy_module, strategy, settings)
  end
  
  @doc """
  Gets statistics about JIT compilation and execution.
  
  ## Parameters
  
  - target: Optional function or module to get stats for. If nil, returns overall stats.
    For JIT-decorated operator modules, automatically retrieves metrics
    from the internal compiled function.
  
  ## Returns
  
  Map with compilation and execution statistics
  """
  @spec get_jit_stats(function() | module() | nil) :: map()
  def get_jit_stats(target \\ nil) do
    Cache.get_metrics(target)
  end
  
  @doc """
  Explains why a particular JIT strategy would be selected.
  
  Useful for understanding and debugging the auto-selection process.
  
  ## Parameters
  
  - target: Function or module to analyze
  
  ## Returns
  
  Map with detailed analysis from each strategy
  """
  @spec explain_jit_selection(function() | module()) :: map()
  def explain_jit_selection(target) do
    trace_strategy = EmberEx.XCS.JIT.Strategies.Trace.new()
    structural_strategy = EmberEx.XCS.JIT.Strategies.Structural.new()
    enhanced_strategy = EmberEx.XCS.JIT.Strategies.Enhanced.new()
    
    %{
      trace: EmberEx.XCS.JIT.Strategies.Trace.score_target(trace_strategy, target, []),
      structural: EmberEx.XCS.JIT.Strategies.Structural.score_target(structural_strategy, target, []),
      enhanced: EmberEx.XCS.JIT.Strategies.Enhanced.score_target(enhanced_strategy, target, [])
    }
  end
  
  # Private helper functions
  
  defp apply_optimization(target, strategy_module, strategy, settings) do
    # Use cond instead of pattern matching for more reliable type checking
    cond do
      is_atom(target) && function_exported?(target, :forward, 1) ->
        # Module-based operator with forward method
        jit_operator_module(target, strategy_module, strategy, settings)
        
      is_atom(target) ->
        # Regular module function
        jit_function(target, strategy_module, strategy, settings)
        
      is_function(target) ->
        # Function-based operator
        jit_function(target, strategy_module, strategy, settings)
        
      is_map(target) && Map.has_key?(target, :__struct__) ->
        # Struct-based operator
        jit_struct_operator(target, strategy_module, strategy, settings)
        
      true ->
        raise "Unsupported target type for JIT optimization: #{inspect(target)}"
    end
  end
  
  defp jit_function(func, strategy_module, strategy, settings) do
    # Compile the function using the selected strategy
    options = [
      force_trace: settings.force_trace,
      sample_input: settings.sample_input,
      cache: settings.custom_cache,
      recursive: settings.recursive,
      preserve_stochasticity: settings.preserve_stochasticity
    ] ++ settings.options
    
    strategy_module.compile(strategy, func, options)
  end
  
  defp jit_operator_module(module, strategy_module, strategy, settings) do
    # For Elixir modules, we need to create a proxy module that will
    # handle the JIT optimization. Since we can't easily modify modules
    # at runtime like in Python's dynamic classes, we'll use a function wrapper.
    
    # Compile the forward function using the selected strategy
    options = [
      force_trace: settings.force_trace,
      sample_input: settings.sample_input,
      cache: settings.custom_cache,
      recursive: settings.recursive,
      preserve_stochasticity: settings.preserve_stochasticity
    ] ++ settings.options
    
    optimized_forward = strategy_module.compile(
      strategy,
      fn inputs -> module.forward(inputs) end,
      options
    )
    
    # Create a wrapper function that preserves the operator interface
    # but uses the optimized forward implementation
    fn inputs when is_map(inputs) ->
      optimized_forward.(inputs)
    end
  end
  
  defp jit_struct_operator(operator, strategy_module, strategy, settings) do
    # For struct-based operators, we need to handle both the forward method
    # and the operator protocol
    
    # Compile options
    options = [
      force_trace: settings.force_trace,
      sample_input: settings.sample_input,
      cache: settings.custom_cache,
      recursive: settings.recursive,
      preserve_stochasticity: settings.preserve_stochasticity
    ] ++ settings.options
    
    # Extract the struct module
    _operator_module = operator.__struct__
    
    # Compile an optimized call function for this specific operator instance
    optimized_call = strategy_module.compile(
      strategy,
      fn inputs -> EmberEx.Operators.Operator.call(operator, inputs) end,
      options
    )
    
    # Return a function that will be used as the optimized operator
    optimized_call
  end
end
