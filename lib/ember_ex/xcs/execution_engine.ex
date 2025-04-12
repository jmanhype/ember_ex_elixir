defmodule EmberEx.XCS.ExecutionEngine do
  @moduledoc """
  Execution engine for running operator graphs with parallelization.
  
  This module provides graph-based execution with parallelization capabilities,
  similar to the XCS component in the Python Ember framework.
  """
  
  @typedoc "Node configuration type"
  @type node_config :: %{
    operator: EmberEx.Operators.Operator.t(),
    inputs: map(),
    dependencies: list(String.t())
  }
  
  @typedoc "Execution plan type"
  @type execution_plan :: %{
    nodes: %{String.t() => node_config},
    dependencies: %{String.t() => list(String.t())},
    execution_order: list(String.t())
  }
  
  @doc """
  Execute a graph of operators.
  
  ## Parameters
  
  - graph: A map where keys are node IDs and values are operator configurations
  - inputs: A map of input values for the graph
  - options: Execution options
  
  ## Returns
  
  A map of output values from the graph execution
  
  ## Examples
  
      iex> graph = %{
      ...>   "node1" => %{
      ...>     operator: my_operator,
      ...>     inputs: %{key: "input_key"},
      ...>     dependencies: []
      ...>   },
      ...>   "node2" => %{
      ...>     operator: another_operator,
      ...>     inputs: %{key: "node1_output"},
      ...>     dependencies: ["node1"]
      ...>   }
      ...> }
      iex> EmberEx.XCS.ExecutionEngine.execute(graph, %{input_key: "value"})
  """
  @spec execute(map(), map(), keyword()) :: map()
  def execute(graph, inputs, options \\ []) do
    # Build the execution plan
    plan = build_execution_plan(graph)
    
    # Execute the plan
    execute_plan(plan, inputs, options)
  end
  
  @doc """
  Build an execution plan from a graph.
  
  ## Parameters
  
  - graph: A map where keys are node IDs and values are operator configurations
  
  ## Returns
  
  An execution plan
  """
  @spec build_execution_plan(map()) :: execution_plan()
  defp build_execution_plan(graph) do
    # Calculate dependencies
    dependencies = calculate_dependencies(graph)
    
    # Calculate execution order using topological sort
    execution_order = topological_sort(dependencies)
    
    %{
      nodes: graph,
      dependencies: dependencies,
      execution_order: execution_order
    }
  end
  
  @doc """
  Execute an execution plan.
  
  ## Parameters
  
  - plan: The execution plan
  - inputs: A map of input values
  - options: Execution options
  
  ## Returns
  
  A map of output values
  """
  @spec execute_plan(execution_plan(), map(), keyword()) :: map()
  defp execute_plan(plan, inputs, options) do
    parallel = Keyword.get(options, :parallel, true)
    
    if parallel do
      execute_parallel(plan, inputs)
    else
      execute_sequential(plan, inputs)
    end
  end
  
  @doc """
  Execute a plan sequentially.
  
  ## Parameters
  
  - plan: The execution plan
  - inputs: A map of input values
  
  ## Returns
  
  A map of output values
  """
  @spec execute_sequential(execution_plan(), map()) :: map()
  defp execute_sequential(plan, inputs) do
    Enum.reduce(plan.execution_order, inputs, fn node_id, acc ->
      node = plan.nodes[node_id]
      node_inputs = extract_node_inputs(node, acc)
      
      # Execute the node
      node_outputs = EmberEx.Operators.Operator.call(node.operator, node_inputs)
      
      # Merge the outputs with a prefix
      node_outputs = Map.new(node_outputs, fn {k, v} -> {"#{node_id}.#{k}", v} end)
      
      # Merge the outputs
      Map.merge(acc, node_outputs)
    end)
  end
  
  @doc """
  Execute a plan in parallel.
  
  ## Parameters
  
  - plan: The execution plan
  - inputs: A map of input values
  
  ## Returns
  
  A map of output values
  """
  @spec execute_parallel(execution_plan(), map()) :: map()
  defp execute_parallel(plan, inputs) do
    # Group nodes by their level in the dependency graph
    levels = group_by_level(plan.dependencies, plan.execution_order)
    
    # Execute each level in parallel, then move to the next level
    Enum.reduce(levels, inputs, fn level_nodes, acc ->
      # Execute all nodes in this level in parallel
      tasks = Enum.map(level_nodes, fn node_id ->
        Task.async(fn ->
          node = plan.nodes[node_id]
          node_inputs = extract_node_inputs(node, acc)
          
          # Execute the node
          node_outputs = EmberEx.Operators.Operator.call(node.operator, node_inputs)
          
          # Prefix the outputs with the node ID
          Map.new(node_outputs, fn {k, v} -> {"#{node_id}.#{k}", v} end)
        end)
      end)
      
      # Wait for all tasks to complete
      results = Task.await_many(tasks)
      
      # Merge all results
      Enum.reduce(results, acc, &Map.merge/2)
    end)
  end
  
  @doc """
  Calculate dependencies for each node in the graph.
  
  ## Parameters
  
  - graph: A map where keys are node IDs and values are operator configurations
  
  ## Returns
  
  A map where keys are node IDs and values are lists of dependency node IDs
  """
  @spec calculate_dependencies(map()) :: %{String.t() => list(String.t())}
  defp calculate_dependencies(graph) do
    Map.new(graph, fn {node_id, node_config} ->
      {node_id, Map.get(node_config, :dependencies, [])}
    end)
  end
  
  @doc """
  Perform a topological sort on the dependency graph.
  
  ## Parameters
  
  - dependencies: A map where keys are node IDs and values are lists of dependency node IDs
  
  ## Returns
  
  A list of node IDs in topological order
  """
  @spec topological_sort(%{String.t() => list(String.t())}) :: list(String.t())
  defp topological_sort(dependencies) do
    # Implementation of Kahn's algorithm for topological sorting
    # Start with nodes that have no dependencies
    no_deps = dependencies
    |> Enum.filter(fn {_, deps} -> Enum.empty?(deps) end)
    |> Enum.map(fn {node, _} -> node end)
    
    do_topological_sort(no_deps, dependencies, [])
  end
  
  @doc """
  Helper function for topological sort.
  
  ## Parameters
  
  - no_deps: A list of nodes with no dependencies
  - dependencies: A map where keys are node IDs and values are lists of dependency node IDs
  - result: The accumulated result
  
  ## Returns
  
  A list of node IDs in topological order
  """
  @spec do_topological_sort(list(String.t()), %{String.t() => list(String.t())}, list(String.t())) :: list(String.t())
  defp do_topological_sort([], _, result), do: Enum.reverse(result)
  defp do_topological_sort([node | rest], dependencies, result) do
    # Remove this node from all dependency lists
    new_deps = Map.new(dependencies, fn {n, deps} ->
      {n, deps -- [node]}
    end)
    
    # Find nodes that now have no dependencies
    new_no_deps = new_deps
    |> Enum.filter(fn {n, deps} -> n != node && Enum.empty?(deps) && n not in result && n not in rest end)
    |> Enum.map(fn {n, _} -> n end)
    
    # Continue with the sort
    do_topological_sort(rest ++ new_no_deps, new_deps, [node | result])
  end
  
  @doc """
  Group nodes by their level in the dependency graph.
  
  ## Parameters
  
  - dependencies: A map where keys are node IDs and values are lists of dependency node IDs
  - execution_order: A list of node IDs in topological order
  
  ## Returns
  
  A list of lists, where each inner list contains nodes at the same level
  """
  @spec group_by_level(%{String.t() => list(String.t())}, list(String.t())) :: list(list(String.t()))
  defp group_by_level(dependencies, execution_order) do
    # Calculate the level of each node
    levels = calculate_levels(dependencies, execution_order)
    
    # Group nodes by level
    max_level = levels |> Map.values() |> Enum.max(fn -> 0 end)
    
    0..max_level
    |> Enum.map(fn level ->
      levels
      |> Enum.filter(fn {_, l} -> l == level end)
      |> Enum.map(fn {node, _} -> node end)
    end)
    |> Enum.filter(fn nodes -> not Enum.empty?(nodes) end)
  end
  
  @doc """
  Calculate the level of each node in the dependency graph.
  
  ## Parameters
  
  - dependencies: A map where keys are node IDs and values are lists of dependency node IDs
  - execution_order: A list of node IDs in topological order
  
  ## Returns
  
  A map where keys are node IDs and values are their levels
  """
  @spec calculate_levels(%{String.t() => list(String.t())}, list(String.t())) :: %{String.t() => integer()}
  defp calculate_levels(dependencies, execution_order) do
    # Start with nodes that have no dependencies at level 0
    initial_levels = dependencies
    |> Enum.filter(fn {_, deps} -> Enum.empty?(deps) end)
    |> Enum.map(fn {node, _} -> {node, 0} end)
    |> Map.new()
    
    # Calculate levels for the rest of the nodes
    Enum.reduce(execution_order, initial_levels, fn node, levels ->
      if Map.has_key?(levels, node) do
        levels
      else
        # The level of a node is 1 + the maximum level of its dependencies
        deps = dependencies[node] || []
        level = deps
        |> Enum.map(fn dep -> Map.get(levels, dep, 0) end)
        |> Enum.max(fn -> -1 end)
        |> Kernel.+(1)
        
        Map.put(levels, node, level)
      end
    end)
  end
  
  @doc """
  Extract inputs for a node from the accumulated outputs.
  
  ## Parameters
  
  - node: The node configuration
  - all_inputs: A map of all available inputs
  
  ## Returns
  
  A map of inputs for the node
  """
  @spec extract_node_inputs(node_config(), map()) :: map()
  defp extract_node_inputs(node, all_inputs) do
    # If the node has explicit input mappings, use those
    case Map.get(node, :inputs) do
      nil -> all_inputs
      inputs when is_map(inputs) ->
        # Map input keys to values from all_inputs
        Map.new(inputs, fn {k, v} ->
          {k, Map.get(all_inputs, v)}
        end)
    end
  end
end
