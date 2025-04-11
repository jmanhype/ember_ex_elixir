defmodule EmberEx.XCS.Schedulers.TopologicalScheduler do
  @moduledoc """
  A scheduler that executes nodes in topological order.
  
  The TopologicalScheduler analyzes the graph to determine a valid execution
  order where all dependencies are satisfied before a node is executed.
  It can optionally parallelize execution within each topological level.
  """
  
  @behaviour EmberEx.XCS.Schedulers.BaseScheduler
  
  require Logger
  
  @typedoc "TopologicalScheduler struct type"
  @type t :: %__MODULE__{
    levels: list(list(String.t())),
    parallel: boolean(),
    max_workers: pos_integer(),
    partial_results: %{optional(String.t()) => map()}
  }
  
  defstruct [
    levels: [],
    parallel: true,
    max_workers: System.schedulers_online(),
    partial_results: %{}
  ]
  
  @doc """
  Create a new TopologicalScheduler with the given options.
  
  ## Parameters
  
  - opts: Options for the scheduler
    - parallel: Whether to parallelize execution within levels (default: true)
    - max_workers: Maximum number of parallel workers (default: number of CPU cores)
  
  ## Returns
  
  A new TopologicalScheduler struct
  
  ## Examples
  
      iex> scheduler = EmberEx.XCS.Schedulers.TopologicalScheduler.new(parallel: true, max_workers: 4)
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      parallel: Keyword.get(opts, :parallel, true),
      max_workers: Keyword.get(opts, :max_workers, System.schedulers_online())
    }
  end
  
  @impl true
  def prepare(scheduler, graph) do
    # Compute topological levels
    levels = compute_topological_levels(graph)
    
    # Store the levels in the scheduler
    %{scheduler | levels: levels, partial_results: %{}}
  end
  
  @impl true
  def execute(scheduler, graph, inputs) do
    # Initialize the results with the inputs
    initial_results = inputs
    
    # Execute each level in sequence
    final_results = Enum.reduce(scheduler.levels, initial_results, fn level, results ->
      # Execute all nodes in the current level
      level_results = execute_level(scheduler, graph, level, results)
      
      # Merge the results
      Map.merge(results, level_results)
    end)
    
    # Update partial results
    _scheduler = %{scheduler | partial_results: final_results}
    
    final_results
  end
  
  @impl true
  def get_partial_results(scheduler) do
    scheduler.partial_results
  end
  
  # Helper function to compute topological levels
  defp compute_topological_levels(graph) do
    # Get all nodes and their dependencies
    nodes = EmberEx.XCS.Graph.get_nodes(graph)
    deps = EmberEx.XCS.Graph.get_dependencies(graph)
    
    # Compute in-degree for each node
    in_degree = Enum.reduce(deps, %{}, fn {_from, to_list}, acc ->
      # Initialize all nodes with in-degree 0
      acc = Enum.reduce(nodes, acc, fn node, acc ->
        Map.put_new(acc, node, 0)
      end)
      
      # Increment in-degree for each dependency
      Enum.reduce(to_list, acc, fn to, acc ->
        Map.update(acc, to, 1, &(&1 + 1))
      end)
    end)
    
    # Compute levels
    compute_levels(nodes, deps, in_degree, [])
  end
  
  # Recursive function to compute levels
  defp compute_levels(nodes, deps, in_degree, levels) do
    # Find nodes with in-degree 0
    current_level = Enum.filter(nodes, fn node ->
      Map.get(in_degree, node, 0) == 0
    end)
    
    # If no nodes have in-degree 0, we're done
    if Enum.empty?(current_level) do
      if Enum.empty?(nodes) do
        # All nodes have been assigned to levels
        Enum.reverse(levels)
      else
        # There's a cycle in the graph
        Logger.error("Cycle detected in graph: #{inspect(nodes)}")
        raise "Cycle detected in graph"
      end
    else
      # Remove current level nodes from the list
      remaining_nodes = nodes -- current_level
      
      # Update in-degree for nodes that depend on the current level
      new_in_degree = Enum.reduce(current_level, in_degree, fn node, acc ->
        # Get nodes that depend on this node
        dependents = Map.get(deps, node, [])
        
        # Decrement in-degree for each dependent
        Enum.reduce(dependents, acc, fn dependent, acc ->
          Map.update(acc, dependent, 0, &(&1 - 1))
        end)
      end)
      
      # Recurse with the next level
      compute_levels(remaining_nodes, deps, new_in_degree, [current_level | levels])
    end
  end
  
  # Execute all nodes in a level
  defp execute_level(scheduler, graph, level, results) do
    if scheduler.parallel do
      # Execute nodes in parallel
      execute_level_parallel(scheduler, graph, level, results)
    else
      # Execute nodes sequentially
      execute_level_sequential(graph, level, results)
    end
  end
  
  # Execute nodes in a level sequentially
  defp execute_level_sequential(graph, level, results) do
    Enum.reduce(level, %{}, fn node_id, acc ->
      # Get the node
      node = EmberEx.XCS.Graph.get_node(graph, node_id)
      
      # Get the node's inputs
      node_inputs = get_node_inputs(graph, node_id, results)
      
      # Execute the node
      node_result = execute_node(node, node_inputs)
      
      # Add the result to the accumulator
      Map.put(acc, node_id, node_result)
    end)
  end
  
  # Execute nodes in a level in parallel
  defp execute_level_parallel(_scheduler, graph, level, results) do
    # Create tasks for each node
    tasks = Enum.map(level, fn node_id ->
      Task.async(fn ->
        # Get the node
        node = EmberEx.XCS.Graph.get_node(graph, node_id)
        
        # Get the node's inputs
        node_inputs = get_node_inputs(graph, node_id, results)
        
        # Execute the node
        node_result = execute_node(node, node_inputs)
        
        # Return the node ID and result
        {node_id, node_result}
      end)
    end)
    
    # Wait for all tasks to complete
    task_results = Task.await_many(tasks, :infinity)
    
    # Convert the list of tuples to a map
    Map.new(task_results)
  end
  
  # Get inputs for a node from the results
  defp get_node_inputs(graph, node_id, results) do
    # Get the node's input dependencies
    input_deps = EmberEx.XCS.Graph.get_input_dependencies(graph, node_id)
    
    # Extract the required inputs from the results
    Enum.reduce(input_deps, %{}, fn {dep_node_id, input_name}, acc ->
      # Get the result from the dependency
      dep_result = Map.get(results, dep_node_id)
      
      # Add the result to the inputs
      Map.put(acc, input_name, dep_result)
    end)
  end
  
  # Execute a single node
  defp execute_node(node, inputs) do
    # Get the operator from the node
    operator = node.operator
    
    # Execute the operator
    EmberEx.Operators.Operator.call(operator, inputs)
  end
end
