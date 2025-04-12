defmodule EmberEx.XCS.JIT.StrategySelector do
  @moduledoc """
  Selects the optimal JIT strategy for target functions.
  
  Implements heuristic policy for determining the most appropriate
  compilation strategy based on function or module characteristics.
  """
  
  require Logger
  alias EmberEx.XCS.JIT.Modes
  
  # Define struct first to avoid compilation issues
  defstruct [strategies: %{}]
  
  @doc """
  Initializes a new strategy selector.
  
  ## Returns
  
  A new StrategySelector struct
  """
  @spec new() :: __MODULE__
  def new do
    # Import strategies
    strategies = %{
      trace: EmberEx.XCS.JIT.Strategies.Trace.new(),
      structural: EmberEx.XCS.JIT.Strategies.Structural.new(),
      enhanced: EmberEx.XCS.JIT.Strategies.Enhanced.new(),
      llm: EmberEx.XCS.JIT.Strategies.LLMStrategy.new()
    }
    
    %__MODULE__{strategies: strategies}
  end
  
  @doc """
  Selects optimal strategy for the target function or module.
  
  ## Parameters
  
  - target: Target function or module to optimize
  - mode: User-specified mode or `:auto` for automatic selection
  
  ## Returns
  
  Most appropriate strategy implementation
  """
  @spec select_strategy(__MODULE__, function() | module(), Modes.t()) :: 
    {module(), term()}
  def select_strategy(%__MODULE__{strategies: strategies}, target, mode \\ :auto) do
    # Use explicit strategy when specified
    if mode != :auto and Map.has_key?(strategies, mode) do
      {get_strategy_module(mode), Map.get(strategies, mode)}
    else
      # Collect and score strategies for auto-selection
      scores = Enum.map(strategies, fn {mode, strategy} ->
        strategy_module = get_strategy_module(mode)
        options = []
        # Call score_target, the updated method from BaseStrategy
        score_result = strategy_module.score_target(strategy, target, options)
        {mode, strategy, score_result}
      end)
      
      # Sort by score in descending order
      sorted_scores = Enum.sort_by(scores, fn {_, _, score_result} -> 
        Map.get(score_result, :score, 0)
      end, :desc)
      
      # Log selection rationale for debugging
      Enum.each(sorted_scores, fn {mode, _, score_result} ->
        Logger.debug("Strategy #{mode} score: #{score_result.score}, rationale: #{score_result.rationale}")
      end)
      
      # Return best strategy
      {mode, strategy, _} = List.first(sorted_scores)
      {get_strategy_module(mode), strategy}
    end
  end
  
  # Helper to get the module for a strategy type
  defp get_strategy_module(:trace), do: EmberEx.XCS.JIT.Strategies.Trace
  defp get_strategy_module(:structural), do: EmberEx.XCS.JIT.Strategies.Structural
  defp get_strategy_module(:enhanced), do: EmberEx.XCS.JIT.Strategies.Enhanced
  defp get_strategy_module(:llm), do: EmberEx.XCS.JIT.Strategies.LLMStrategy
end
