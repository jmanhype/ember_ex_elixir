defmodule EmberEx.XCS.JIT.Strategies.StructuralStrategy do
  @moduledoc """
  A JIT optimization strategy that analyzes and optimizes operator structures.
  
  This strategy focuses on optimizing the structure of operator pipelines,
  including operator fusion, dead code elimination, and operator reordering.
  It is particularly effective for complex pipelines with many operators.
  """
  
  alias EmberEx.Operators.Operator
  alias EmberEx.Operators.{SequenceOperator, MapOperator, ParallelOperator}
  
  @typedoc """
  Analysis result containing structure information and optimization opportunities
  """
  @type analysis_result :: %{
    score: integer(),
    rationale: String.t(),
    optimization_targets: list(map()),
    structural_properties: map()
  }
  
  @doc """
  Returns the name of this strategy.
  """
  @spec name() :: String.t()
  def name, do: "structural"
  
  @doc """
  Analyzes an operator's structure to identify optimization opportunities.
  
  This function:
  1. Examines the operator's structure and component relationships
  2. Identifies patterns like sequential map operations that can be fused
  3. Looks for redundant operations or dead code
  4. Finds opportunities for parallelization
  
  ## Parameters
    * `operator` - The operator to analyze
    * `inputs` - Sample inputs used for analysis
    
  ## Returns
    * An analysis result containing structure information and optimization score
  """
  @spec analyze(Operator.t(), map()) :: analysis_result()
  def analyze(operator, _inputs) do
    # Analyze operator structure
    {complexity, depth} = analyze_complexity(operator)
    fusion_opportunities = identify_fusion_opportunities(operator)
    parallelizable_sections = identify_parallelizable_sections(operator)
    
    # Calculate optimization potential
    {score, rationale} = calculate_score(
      complexity, 
      depth, 
      fusion_opportunities, 
      parallelizable_sections
    )
    
    # Create analysis result
    %{
      score: score,
      rationale: rationale,
      optimization_targets: fusion_opportunities ++ parallelizable_sections,
      structural_properties: %{
        complexity: complexity,
        depth: depth,
        sequential_chains: count_sequential_chains(operator),
        parallel_sections: count_parallel_sections(operator)
      }
    }
  end
  
  @doc """
  Compiles an optimized version of the operator based on structural analysis.
  
  This function:
  1. Applies structural optimizations identified in the analysis
  2. Fuses compatible operator sequences
  3. Parallelizes independent sections
  4. Simplifies the operator graph
  
  ## Parameters
    * `operator` - The original operator to optimize
    * `inputs` - Sample inputs used for optimization planning
    * `analysis` - Analysis results from the `analyze/2` function
    
  ## Returns
    * An optimized operator with improved structure
  """
  @spec compile(Operator.t(), map(), any()) :: Operator.t()
  def compile(operator, _inputs, analysis) do
    # First validate that we have a proper analysis result
    case analysis do
      # Analysis is a valid map with a score
      %{score: score} when is_integer(score) ->
        if score < 25 do
          # Not worth optimizing
          operator
        else
          # Apply structural optimizations with nil protection
          targets = Map.get(analysis, :optimization_targets, [])
          result = operator
            |> apply_fusion_optimizations(targets)
            |> apply_parallelization(targets)
            |> simplify_graph()
          
          # Safety check to ensure we never return nil
          case result do
            nil -> 
              # Log the issue for debugging
              require Logger
              Logger.warning("StructuralStrategy optimization resulted in nil, returning original operator")
              operator
            result -> result
          end
        end
        
      # Invalid or missing analysis structure
      _ ->
        require Logger
        Logger.warning("StructuralStrategy received invalid analysis: #{inspect(analysis)}")
        operator
    end
  rescue
    error ->
      require Logger
      Logger.warning("StructuralStrategy error during compilation: #{inspect(error)}")
      operator
  end
  
  # Private helper functions
  
  @spec analyze_complexity(Operator.t()) :: {integer(), integer()}
  defp analyze_complexity(operator) do
    case operator do
      %SequenceOperator{operators: ops} ->
        # Calculate maximum depth and total complexity
        {max_complexity, max_depth} = 
          Enum.map(ops, &analyze_complexity/1)
          |> Enum.reduce({0, 0}, fn {comp, depth}, {max_comp, max_depth} ->
            {max(comp, max_comp), max(depth, max_depth)}
          end)
        
        {Enum.count(ops) + max_complexity, 1 + max_depth}
        
      %ParallelOperator{operators: ops} ->
        # Calculate maximum depth and total complexity
        {sum_complexity, max_depth} = 
          Enum.map(ops, &analyze_complexity/1)
          |> Enum.reduce({0, 0}, fn {comp, depth}, {sum_comp, max_depth} ->
            {sum_comp + comp, max(depth, max_depth)}
          end)
        
        {sum_complexity, 1 + max_depth}
        
      _other ->
        # Base operator has complexity 1 and depth 1
        {1, 1}
    end
  end
  
  @spec identify_fusion_opportunities(Operator.t()) :: list(map())
  defp identify_fusion_opportunities(operator) do
    case operator do
      %SequenceOperator{operators: ops} ->
        # Find sequential MapOperators that can be fused
        map_pairs = find_sequential_map_operators(ops)
        
        # Create fusion targets
        map_pairs
        |> Enum.map(fn {idx, op1, op2} ->
          %{
            type: :fusion,
            target: [idx, idx + 1],
            operators: [op1, op2],
            reason: "Sequential map operators can be fused"
          }
        end)
        |> Enum.concat(
          # Recursively check nested operators
          Enum.flat_map(ops, &identify_fusion_opportunities/1)
        )
        
      %ParallelOperator{operators: ops} ->
        # Check for fusion opportunities in each parallel branch
        Enum.flat_map(ops, &identify_fusion_opportunities/1)
        
      _other ->
        []
    end
  end
  
  @spec find_sequential_map_operators(list(Operator.t())) :: 
    list({integer(), MapOperator.t(), MapOperator.t()})
  defp find_sequential_map_operators(operators) do
    operators
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.with_index()
    |> Enum.filter(fn {[op1, op2], _idx} -> 
      match?(%MapOperator{}, op1) and match?(%MapOperator{}, op2)
    end)
    |> Enum.map(fn {[op1, op2], idx} -> {idx, op1, op2} end)
  end
  
  @spec identify_parallelizable_sections(Operator.t()) :: list(map())
  defp identify_parallelizable_sections(operator) do
    case operator do
      %SequenceOperator{operators: ops} ->
        # Identify independent operations that could be parallelized
        # This is a simplified version - a real implementation would
        # analyze data dependencies between operations
        independent_groups = find_independent_operations(ops)
        
        parallel_targets = independent_groups
        |> Enum.map(fn indices ->
          target_ops = Enum.map(indices, &Enum.at(ops, &1))
          %{
            type: :parallelization,
            target: indices,
            operators: target_ops,
            reason: "Independent operations can be parallelized"
          }
        end)
        
        # Also check nested operators
        nested_targets = Enum.flat_map(ops, &identify_parallelizable_sections/1)
        
        parallel_targets ++ nested_targets
        
      %ParallelOperator{operators: ops} ->
        # Check for parallelizable sections in each branch
        Enum.flat_map(ops, &identify_parallelizable_sections/1)
        
      _other ->
        []
    end
  end
  
  @spec find_independent_operations(list(Operator.t())) :: list(list(integer()))
  defp find_independent_operations(operators) do
    # This is a simplified implementation
    # In a real scenario, we would analyze data dependencies
    
    # For now, just identify any MapOperators that could potentially
    # be executed in parallel
    operators
    |> Enum.with_index()
    |> Enum.filter(fn {op, _idx} -> match?(%MapOperator{}, op) end)
    |> Enum.map(fn {_op, idx} -> idx end)
    |> group_independent_operations([])
  end
  
  @spec group_independent_operations(list(integer()), list(list(integer()))) :: 
    list(list(integer()))
  defp group_independent_operations([], groups), do: groups
  defp group_independent_operations(indices, groups) do
    # This is a simplified grouping algorithm
    # Group indices that are far enough apart to be considered independent
    # In reality, this needs data dependency analysis
    if length(indices) >= 2 do
      [group_1, group_2 | rest] = indices
      # Add a new group
      group_independent_operations(
        rest, 
        [[group_1, group_2] | groups]
      )
    else
      # Not enough indices for a group
      groups
    end
  end
  
  @spec calculate_score(integer(), integer(), list(map()), list(map())) :: 
    {integer(), String.t()}
  defp calculate_score(complexity, depth, fusion_opportunities, parallelizable_sections) do
    # Base score based on complexity and depth
    base_score = min(50, complexity * 2 + depth * 5)
    
    # Additional score based on optimization opportunities
    fusion_score = min(25, length(fusion_opportunities) * 10)
    parallel_score = min(25, length(parallelizable_sections) * 15)
    
    total_score = base_score + fusion_score + parallel_score
    capped_score = min(100, total_score)
    
    rationale = "Structural analysis found #{complexity} operators with depth #{depth}, " <>
                "#{length(fusion_opportunities)} fusion opportunities, and " <>
                "#{length(parallelizable_sections)} parallelizable sections"
    
    {capped_score, rationale}
  end
  
  @spec count_sequential_chains(Operator.t()) :: integer()
  defp count_sequential_chains(operator) do
    case operator do
      %SequenceOperator{operators: ops} ->
        1 + Enum.sum(Enum.map(ops, &count_sequential_chains/1))
      %ParallelOperator{operators: ops} ->
        Enum.sum(Enum.map(ops, &count_sequential_chains/1))
      _other -> 0
    end
  end
  
  @spec count_parallel_sections(Operator.t()) :: integer()
  defp count_parallel_sections(operator) do
    case operator do
      %ParallelOperator{operators: ops} ->
        1 + Enum.sum(Enum.map(ops, &count_parallel_sections/1))
      %SequenceOperator{operators: ops} ->
        Enum.sum(Enum.map(ops, &count_parallel_sections/1))
      _other -> 0
    end
  end
  
  @spec apply_fusion_optimizations(Operator.t(), list(map())) :: Operator.t()
  defp apply_fusion_optimizations(operator, targets) do
    # Extract fusion targets
    fusion_targets = Enum.filter(targets, fn t -> t.type == :fusion end)
    
    # Apply fusion optimizations
    case {operator, fusion_targets} do
      {%SequenceOperator{operators: ops}, [target | _]} when length(target.target) == 2 ->
        # Get the indices to fuse
        [idx1, idx2] = target.target
        
        # Get the operators to fuse
        op1 = Enum.at(ops, idx1)
        op2 = Enum.at(ops, idx2)
        
        # Create the fused operator
        fused_op = fuse_map_operators(op1, op2)
        
        # Create a new operator list with the fused operator
        new_ops = 
          Enum.take(ops, idx1) ++ 
          [fused_op] ++ 
          Enum.drop(ops, idx2 + 1)
        
        # Create new sequence with fused operators
        fused_sequence = %SequenceOperator{operators: new_ops}
        
        # Continue fusion with remaining targets
        remaining_targets = Enum.drop(fusion_targets, 1)
        apply_fusion_optimizations(fused_sequence, remaining_targets)
        
      {_, [_ | rest]} ->
        # If we can't fuse at this level, try the next target
        apply_fusion_optimizations(operator, rest)
        
      {%SequenceOperator{operators: ops}, []} ->
        # No more fusion targets at this level, apply recursively to children
        %SequenceOperator{operators: Enum.map(ops, &apply_fusion_optimizations(&1, targets))}
        
      {%ParallelOperator{operators: ops}, []} ->
        # No fusion targets at this level, apply recursively to children
        %ParallelOperator{operators: Enum.map(ops, &apply_fusion_optimizations(&1, targets))}
        
      {_, []} ->
        # Base case, no more fusion to do
        operator
    end
  end
  
  @spec fuse_map_operators(MapOperator.t(), MapOperator.t()) :: MapOperator.t()
  defp fuse_map_operators(%MapOperator{} = op1, %MapOperator{} = op2) do
    # Create a new function that combines both map operations
    combined_fn = fn input ->
      intermediate = op1.function.(input)
      op2.function.(intermediate)
    end
    
    # Create the fused operator
    %MapOperator{
      function: combined_fn,
      input_key: op1.input_key,
      output_key: op2.output_key
    }
  end
  
  @spec apply_parallelization(Operator.t(), list(map())) :: Operator.t()
  defp apply_parallelization(operator, targets) do
    # Extract parallelization targets
    parallel_targets = Enum.filter(targets, fn t -> t.type == :parallelization end)
    
    # Apply parallelization optimizations
    case {operator, parallel_targets} do
      {%SequenceOperator{operators: ops}, [target | _]} ->
        # Get the indices to parallelize
        indices = target.target
        
        # Extract operators to parallelize
        parallel_ops = Enum.map(indices, &Enum.at(ops, &1))
        
        # Create a parallel operator
        parallel_op = %ParallelOperator{operators: parallel_ops}
        
        # Create new sequence without the parallelized operators
        remaining_indices = MapSet.new(0..(length(ops) - 1))
          |> MapSet.difference(MapSet.new(indices))
          |> MapSet.to_list()
          |> Enum.sort()
        
        remaining_ops = Enum.map(remaining_indices, &Enum.at(ops, &1))
        
        # Determine where to insert the parallel operator
        # (simplified: insert at the minimum index of the parallelized ops)
        min_idx = Enum.min(indices)
        
        # Build the new operator list
        new_ops = 
          Enum.take(remaining_ops, min_idx) ++ 
          [parallel_op] ++ 
          Enum.drop(remaining_ops, min_idx)
        
        # Create new sequence with parallel operator
        new_sequence = %SequenceOperator{operators: new_ops}
        
        # Continue with remaining targets
        remaining_targets = Enum.drop(parallel_targets, 1)
        apply_parallelization(new_sequence, remaining_targets)
        
      {_, [_ | rest]} ->
        # If we can't parallelize at this level, try the next target
        apply_parallelization(operator, rest)
        
      {%SequenceOperator{operators: ops}, []} ->
        # No more parallelization targets at this level, apply recursively
        %SequenceOperator{operators: Enum.map(ops, &apply_parallelization(&1, targets))}
        
      {%ParallelOperator{operators: ops}, []} ->
        # No parallelization targets at this level, apply recursively
        %ParallelOperator{operators: Enum.map(ops, &apply_parallelization(&1, targets))}
        
      {_, []} ->
        # Base case, no more parallelization to do
        operator
    end
  end
  
  @spec simplify_graph(Operator.t()) :: Operator.t()
  defp simplify_graph(operator) do
    case operator do
      %SequenceOperator{operators: [single_op]} ->
        # Simplify single-operator sequences
        simplify_graph(single_op)
        
      %SequenceOperator{operators: ops} ->
        # Flatten nested sequences
        flattened_ops = Enum.flat_map(ops, fn op ->
          simplified = simplify_graph(op)
          case simplified do
            %SequenceOperator{operators: nested_ops} -> nested_ops
            other -> [other]
          end
        end)
        
        %SequenceOperator{operators: flattened_ops}
        
      %ParallelOperator{operators: [single_op]} ->
        # Simplify single-operator parallels
        simplify_graph(single_op)
        
      %ParallelOperator{operators: ops} ->
        # Simplify each parallel branch
        %ParallelOperator{operators: Enum.map(ops, &simplify_graph/1)}
        
      _other ->
        # Base operator remains unchanged
        operator
    end
  end
end
