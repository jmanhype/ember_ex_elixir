defmodule EmberEx.XCS.JIT.Strategies.EnhancedStrategy do
  @moduledoc """
  An advanced JIT optimization strategy that combines multiple optimization approaches.
  
  This strategy integrates structural, trace-based, and specialized optimizations
  to provide comprehensive performance improvements for operator pipelines.
  It selectively applies the most effective techniques based on operator characteristics.
  """
  
  alias EmberEx.Operators.Operator
  alias EmberEx.XCS.JIT.Strategies.{StructuralStrategy, TraceStrategy, LLMStrategy}
  
  @typedoc """
  Enhanced analysis result combining multiple optimization strategies
  """
  @type analysis_result :: %{
    score: integer(),
    rationale: String.t(),
    structural_score: integer(),
    trace_score: integer(),
    llm_score: integer(),
    structural_analysis: map() | nil,
    trace_analysis: map() | nil,
    llm_analysis: map() | nil,
    combined_targets: list(map())
  }
  
  @doc """
  Returns the name of this strategy.
  """
  @spec name() :: String.t()
  def name, do: "enhanced"
  
  @doc """
  Analyzes an operator using multiple strategies and combines the results.
  
  This function:
  1. Applies structural, trace-based, and LLM-specific analyses
  2. Weights and combines the scores from each strategy
  3. Identifies the most promising optimization targets
  4. Creates a comprehensive optimization plan
  
  ## Parameters
    * `operator` - The operator to analyze
    * `inputs` - Sample inputs used for analysis
    
  ## Returns
    * A comprehensive analysis result with combined optimization score
  """
  @spec analyze(Operator.t(), map()) :: analysis_result()
  def analyze(operator, inputs) do
    # Apply individual strategies
    structural_analysis = analyze_with_strategy(StructuralStrategy, operator, inputs)
    trace_analysis = analyze_with_strategy(TraceStrategy, operator, inputs)
    llm_analysis = analyze_with_strategy(LLMStrategy, operator, inputs)
    
    # Extract scores
    structural_score = get_score(structural_analysis)
    trace_score = get_score(trace_analysis)
    llm_score = get_score(llm_analysis)
    
    # Combine optimization targets
    combined_targets = combine_optimization_targets([
      {structural_analysis, :structural},
      {trace_analysis, :trace},
      {llm_analysis, :llm}
    ])
    
    # Calculate combined score with weighting
    {score, rationale} = calculate_combined_score(
      structural_score,
      trace_score,
      llm_score,
      combined_targets
    )
    
    # Create comprehensive analysis result
    %{
      score: score,
      rationale: rationale,
      structural_score: structural_score,
      trace_score: trace_score,
      llm_score: llm_score,
      structural_analysis: structural_analysis,
      trace_analysis: trace_analysis,
      llm_analysis: llm_analysis,
      combined_targets: combined_targets
    }
  end
  
  @doc """
  Compile an optimized version of the operator based on the analysis.
  
  This function combines the optimization targets from multiple strategies
  and applies them in order of priority, starting with the highest-scoring
  targets.
  
  ## Parameters
  
  - operator: The operator to optimize
  - inputs: The inputs to the operator (for reference)
  - analysis: The analysis result from analyze/2
  
  ## Returns
  
  An optimized operator implementation. If no optimizations can be applied,
  returns the original operator.
  """
  @spec compile(Operator.t(), map(), map()) :: Operator.t()
  def compile(operator, inputs, analysis) do
    # We'll track whether any optimizations are applied
    case optimize_with_strategies(operator, inputs, analysis) do
      nil -> 
        require Logger
        Logger.warning("Enhanced strategy could not compile an optimized operator, returning original")
        operator
      optimized -> 
        optimized
    end
  end
  
  # Private helper functions
  
  @spec analyze_with_strategy(module(), Operator.t(), map()) :: map() | nil
  defp analyze_with_strategy(strategy_module, operator, inputs) do
    try do
      if function_exported?(strategy_module, :analyze, 2) do
        strategy_module.analyze(operator, inputs)
      else
        nil
      end
    rescue
      _ -> nil
    end
  end
  
  @spec get_score(map() | nil) :: integer()
  defp get_score(nil), do: 0
  defp get_score(analysis) when is_map(analysis) do
    Map.get(analysis, :score, 0)
  end
  
  @spec combine_optimization_targets(list({map() | nil, atom()})) :: list(map())
  defp combine_optimization_targets(analyses) do
    analyses
    |> Enum.flat_map(fn {analysis, strategy_type} ->
      case analysis do
        nil -> []
        analysis when is_map(analysis) ->
          # Extract optimization targets and tag with strategy type
          targets = Map.get(analysis, :optimization_targets, [])
          Enum.map(targets, fn target ->
            Map.put(target, :source_strategy, strategy_type)
          end)
      end
    end)
    |> prioritize_targets()
  end
  
  @spec prioritize_targets(list(map())) :: list(map())
  defp prioritize_targets(targets) do
    # Sort targets by priority
    targets
    |> Enum.sort_by(fn target ->
      # Calculate priority based on target type and source strategy
      priority_score(target)
    end, :desc)
  end
  
  @spec priority_score(map()) :: integer()
  defp priority_score(target) do
    # Base priority by source strategy
    strategy_priority = case target[:source_strategy] do
      :structural -> 100
      :llm -> 80
      :trace -> 60
      _ -> 0
    end
    
    # Additional priority by target type
    type_priority = case target[:type] do
      :fusion -> 50
      :parallelization -> 40
      :caching -> 30
      :specialization -> 20
      _ -> 0
    end
    
    strategy_priority + type_priority
  end
  
  @spec calculate_combined_score(integer(), integer(), integer(), list(map())) :: 
    {integer(), String.t()}
  defp calculate_combined_score(structural_score, trace_score, llm_score, combined_targets) do
    # Weight the scores from different strategies
    weighted_structural = structural_score * 0.4
    weighted_trace = trace_score * 0.3
    weighted_llm = llm_score * 0.3
    
    # Base combined score
    base_score = weighted_structural + weighted_trace + weighted_llm
    
    # Bonus for having multiple high-scoring strategies
    strategy_synergy = if structural_score > 50 and (trace_score > 40 or llm_score > 40) do
      15
    else
      0
    end
    
    # Bonus for having many optimization targets
    target_bonus = min(10, length(combined_targets) * 2)
    
    # Calculate final score
    total_score = base_score + strategy_synergy + target_bonus
    capped_score = min(100, round(total_score))
    
    # Generate rationale
    rationale = "Combined LLM and structural optimizations for maximum efficiency"
    
    {capped_score, rationale}
  end
  
  @spec optimize_with_strategies(Operator.t(), map(), map()) :: Operator.t() | nil
  defp optimize_with_strategies(operator, inputs, analysis) do
    # If no analysis available, return nil (no optimization)
    unless analysis do
      nil
    else
      # Get optimization targets sorted by score (highest first)
      highest_structural_score = analysis[:structural_score] || 0
      highest_trace_score = analysis[:trace_score] || 0
      highest_llm_score = analysis[:llm_score] || 0
      
      # Apply each strategy based on its score
      optimized_operator = operator
      
      # Track if we applied any optimizations
      _optimizations_applied = false
      
      # Apply structural strategy if score is high enough
      {optimized_operator, structural_changed} = if highest_structural_score >= 30 do
        case apply_strategy(StructuralStrategy, optimized_operator, analysis, inputs) do
          nil -> {optimized_operator, false}
          new_op -> {new_op, true}
        end
      else
        {optimized_operator, false}
      end
      
      # Apply trace strategy if score is high enough
      {optimized_operator, trace_changed} = if highest_trace_score >= 30 do
        case apply_strategy(TraceStrategy, optimized_operator, analysis, inputs) do
          nil -> {optimized_operator, false}
          new_op -> {new_op, true}
        end
      else
        {optimized_operator, false}
      end
      
      # Apply LLM strategy if score is high enough
      {optimized_operator, llm_changed} = if highest_llm_score >= 30 do
        case apply_strategy(LLMStrategy, optimized_operator, analysis, inputs) do
          nil -> {optimized_operator, false}
          new_op -> {new_op, true}
        end
      else
        {optimized_operator, false}
      end
      
      # Return the optimized operator if any changes were made, otherwise nil
      if structural_changed || trace_changed || llm_changed do
        optimized_operator
      else
        nil
      end
    end
  rescue
    e -> 
      # Log the error for debugging
      require Logger
      Logger.warning("Error in EnhancedStrategy: #{inspect(e)}")
      nil
  end
  
  @spec apply_strategy(module(), Operator.t(), map(), map()) :: Operator.t() | nil
  defp apply_strategy(strategy_module, operator, analysis, _inputs) do
    # Extract the strategy-specific analysis
    strategy_key = case strategy_module do
      StructuralStrategy -> :structural_analysis
      TraceStrategy -> :trace_analysis
      LLMStrategy -> :llm_analysis
      _ -> nil
    end
    
    # Apply the strategy if we have the analysis
    if strategy_key && analysis[strategy_key] do
      strategy_analysis = analysis[strategy_key]
      # Call the strategy's compile function
      try do
        strategy_result = strategy_module.compile(strategy_module, operator, strategy_analysis)
        
        # Validate the strategy result
        if is_struct(strategy_result) or is_function(strategy_result, 1) do
          strategy_result
        else
          require Logger
          Logger.warning("Strategy module #{inspect(strategy_module)} returned invalid operator type: #{inspect(strategy_result)}")
          nil
        end
      rescue
        e -> 
          require Logger
          Logger.warning("Error calling #{inspect(strategy_module)}.compile: #{inspect(e)}")
          nil
      end
    else
      # No analysis for this strategy, so no change
      nil
    end
  end
end
