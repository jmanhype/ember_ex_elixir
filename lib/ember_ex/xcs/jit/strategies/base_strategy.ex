defmodule EmberEx.XCS.JIT.Strategies.BaseStrategy do
  @moduledoc """
  Base behaviour for JIT compilation strategies.
  
  Defines the interface that all JIT strategies must implement, along with
  common utility functions shared across strategies.
  
  ## Usage
  
  ```elixir
  defmodule MyStrategy do
    use EmberEx.XCS.JIT.Strategies.BaseStrategy
    
    # Implement callback functions
    def compile(strategy, target, options) do
      # Implementation
    end
    
    def score_target(strategy, target, options) do
      # Implementation
    end
  end
  ```
  """
  
  require Logger
  alias EmberEx.XCS.JIT.Cache
  
  @doc false
  defmacro __using__(_opts) do
    quote do
      @behaviour EmberEx.XCS.JIT.Strategies.BaseStrategy
      use EmberEx.XCS.JIT.Strategies.JITFallbackMixin
      
      alias EmberEx.XCS.JIT.Cache
      require Logger
    end
  end
  
  @doc """
  Scores a target to determine how suitable it is for this strategy.
  
  ## Parameters
  
  - strategy: The strategy struct
  - target: Function or operator to analyze
  - options: Optional parameters for scoring
  
  ## Returns
  
  A tuple {score, rationale} where score is a number from 0-100 and
  rationale is a string explaining the score
  """
  @callback score_target(strategy :: struct(), target :: any(), options :: keyword()) :: {number(), String.t()}
  
  @doc """
  Compiles a function or operator using this strategy.
  
  ## Parameters
  
  - strategy: The strategy struct
  - target: Function or operator to compile
  - options: Compilation options
  
  ## Returns
  
  Compiled function that behaves like the original but with optimizations
  """
  @callback compile(strategy :: struct(), target :: any(), options :: keyword()) :: function()
  
  @doc """
  Executes a compiled graph with fallback to direct execution.
  
  ## Parameters
  
  - graph: Compiled execution graph
  - original: Original function or operator
  - inputs: Input values
  
  ## Returns
  
  Execution result
  """
  @callback execute_with_fallback(graph :: term(), original :: function() | module(), inputs :: map()) :: term()
  
  @doc """
  Extracts common features from a target function or module for analysis.
  
  ## Parameters
  
  - target: Function or operator to analyze
  
  ## Returns
  
  Map of common features
  """
  @spec extract_common_features(function() | module()) :: map()
  def extract_common_features(target) do
    is_class = is_atom(target) and Code.ensure_loaded?(target)
    has_operator_protocol = is_class and function_exported?(target, :call, 1)
    has_forward_method = is_class and function_exported?(target, :forward, 1)
    has_specification = is_class and function_exported?(target, :specification, 0)
    
    %{
      is_class: is_class,
      is_function: is_function(target),
      has_operator_protocol: has_operator_protocol,
      has_forward_method: has_forward_method,
      has_specification: has_specification
    }
  end
  
  @doc """
  Gets a JIT cache instance.
  
  ## Parameters
  
  - custom_cache: Optional custom cache to use
  
  ## Returns
  
  JIT cache module
  """
  @spec get_cache(term() | nil) :: module()
  def get_cache(_custom_cache = nil), do: EmberEx.XCS.JIT.Cache
  def get_cache(custom_cache), do: custom_cache
end

defmodule EmberEx.XCS.JIT.Strategies.JITFallbackMixin do
  @moduledoc """
  Provides a standard implementation for the `execute_with_fallback` function.
  
  This module can be used with `use` to provide the standard implementation
  of the fallback execution logic for JIT strategies.
  """
  
  @doc false
  defmacro __using__(_) do
    quote do
      alias EmberEx.XCS.JIT.Cache
      require Logger
      
      @doc """
      Executes a compiled graph with fallback to direct execution.
      
      ## Parameters
      
      - graph: Compiled execution graph
      - original: Original function or operator
      - inputs: Input values
      
      ## Returns
      
      Execution result
      """
      @spec execute_with_fallback(term(), function() | module(), map()) :: term()
      def execute_with_fallback(graph, original, inputs) do
        try do
          # Try to execute the compiled graph
          EmberEx.XCS.JIT.ExecutionUtils.execute_compiled_graph(graph, inputs, original)
        rescue
          e ->
            # Log error and fall back to direct execution
            Logger.warning("Error executing compiled graph: #{inspect(e)}. Falling back to direct execution.")
            
            # Execute directly and time it
            execution_start = :os.system_time(:millisecond) / 1000
            result = execute_original(original, inputs)
            execution_duration = :os.system_time(:millisecond) / 1000 - execution_start
            
            Cache.record_execution(original, execution_duration)
            result
        end
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
  end
end
