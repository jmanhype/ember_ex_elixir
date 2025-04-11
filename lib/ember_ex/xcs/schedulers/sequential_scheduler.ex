defmodule EmberEx.XCS.Schedulers.SequentialScheduler do
  @moduledoc """
  A scheduler that executes nodes sequentially in topological order.
  
  The SequentialScheduler analyzes the graph to determine a valid execution
  order where all dependencies are satisfied before a node is executed.
  It executes nodes one at a time in this order.
  """
  
  @behaviour EmberEx.XCS.Schedulers.BaseScheduler
  
  require Logger
  
  @typedoc "SequentialScheduler struct type"
  @type t :: %__MODULE__{
    execution_order: list(String.t()),
    partial_results: %{optional(String.t()) => map()}
  }
  
  defstruct [
    execution_order: [],
    partial_results: %{}
  ]
  
  @doc """
  Create a new SequentialScheduler with the given options.
  
  ## Parameters
  
  - opts: Options for the scheduler (currently unused)
  
  ## Returns
  
  A new SequentialScheduler struct
  
  ## Examples
  
      iex> scheduler = EmberEx.XCS.Schedulers.SequentialScheduler.new()
  """
  @spec new(keyword()) :: t()
  def new(_opts \\ []) do
    %__MODULE__{}
  end
  
  @impl true
  def prepare(scheduler, graph) do
    # Compute a topological sort of the nodes
    execution_order = compute_execution_order(graph)
    
    # Store the execution order in the scheduler
    %{scheduler | execution_order: execution_order, partial_results: %{}}
  end
  
  @impl true
  def execute(scheduler, graph, inputs) do
    # Prepare the scheduler if not already prepared
    prepared_scheduler = prepare(scheduler, graph)
    
    # Initialize the results with the inputs
    initial_results = inputs
    
    # Execute each node in sequence
    final_results = Enum.reduce(prepared_scheduler.execution_order, initial_results, fn node_id, results ->
      # Get the node
      node = EmberEx.XCS.Graph.get_node(graph, node_id)
      
      # Get the node's inputs
      node_inputs = get_node_inputs(graph, node_id, results)
      
      # Execute the node
      node_result = execute_node(node, node_inputs)
      
      # Add the result to the accumulator
      Map.put(results, node_id, node_result)
    end)
    
    # Update partial results
    _scheduler = %{prepared_scheduler | partial_results: final_results}
    
    final_results
  end
  
  @impl true
  def get_partial_results(scheduler) do
    scheduler.partial_results
  end
  
  # Helper function to compute execution order
  defp compute_execution_order(graph) do
    # Get all nodes and their dependencies
    nodes = EmberEx.XCS.Graph.get_nodes(graph)
    deps = EmberEx.XCS.Graph.get_dependencies(graph)
    
    # Perform a topological sort
    topological_sort(nodes, deps)
  end
  
  # Topological sort algorithm
  defp topological_sort(nodes, deps) do
    # Initialize visited and temp_mark sets
    visited = MapSet.new()
    temp_mark = MapSet.new()
    
    # Initialize the result list
    result = []
    
    # Visit each node
    {result, _visited, _temp_mark} = Enum.reduce(nodes, {result, visited, temp_mark}, fn node, {result, visited, temp_mark} ->
      if MapSet.member?(visited, node) do
        {result, visited, temp_mark}
      else
        visit(node, deps, result, visited, temp_mark)
      end
    end)
    
    # Return the result in reverse order (topological sort)
    Enum.reverse(result)
  end
  
  # Visit a node in the topological sort
  defp visit(node, deps, result, visited, temp_mark) do
    # Check for cycles
    if MapSet.member?(temp_mark, node) do
      Logger.error("Cycle detected in graph at node: #{node}")
      raise "Cycle detected in graph"
    end
    
    # If already visited, return the current state
    if MapSet.member?(visited, node) do
      {result, visited, temp_mark}
    else
      # Mark the node as temporarily visited
      temp_mark = MapSet.put(temp_mark, node)
      
      # Visit all dependencies
      dependents = Map.get(deps, node, [])
      {result, visited, temp_mark} = Enum.reduce(dependents, {result, visited, temp_mark}, fn dependent, {result, visited, temp_mark} ->
        visit(dependent, deps, result, visited, temp_mark)
      end)
      
      # Mark the node as visited
      visited = MapSet.put(visited, node)
      
      # Remove the temporary mark
      temp_mark = MapSet.delete(temp_mark, node)
      
      # Add the node to the result
      {[node | result], visited, temp_mark}
    end
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
