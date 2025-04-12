defmodule EmberEx.XCS.Schedulers.WaveScheduler do
  @moduledoc """
  A scheduler that executes nodes in waves of parallel execution.
  
  The WaveScheduler analyzes the graph to determine which nodes can be
  executed in parallel, respecting dependencies between nodes. It uses
  a wave-based approach where each wave consists of nodes that can be
  executed in parallel, and waves are executed sequentially.
  """
  
  @behaviour EmberEx.XCS.Schedulers.BaseScheduler
  
  require Logger
  
  @typedoc "WaveScheduler struct type"
  @type t :: %__MODULE__{
    waves: list(list(String.t())),
    max_workers: pos_integer(),
    partial_results: %{optional(String.t()) => map()}
  }
  
  defstruct [
    waves: [],
    max_workers: System.schedulers_online(),
    partial_results: %{}
  ]
  
  @doc """
  Create a new WaveScheduler with the given options.
  
  ## Parameters
  
  - opts: Options for the scheduler
    - max_workers: Maximum number of parallel workers per wave (default: number of CPU cores)
  
  ## Returns
  
  A new WaveScheduler struct
  
  ## Examples
  
      iex> scheduler = EmberEx.XCS.Schedulers.WaveScheduler.new(max_workers: 4)
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      max_workers: Keyword.get(opts, :max_workers, System.schedulers_online())
    }
  end
  
  @impl true
  def prepare(scheduler, graph) do
    # Compute waves of nodes that can be executed in parallel
    waves = compute_waves(graph)
    
    # Store the waves in the scheduler
    %{scheduler | waves: waves, partial_results: %{}}
  end
  
  @impl true
  def execute(scheduler, graph, inputs) do
    # Prepare the scheduler
    prepared_scheduler = prepare(scheduler, graph)
    
    # Initialize the results with the inputs
    initial_results = inputs
    
    # Execute each wave in sequence
    final_results = Enum.reduce(prepared_scheduler.waves, initial_results, fn wave, results ->
      # Execute all nodes in the current wave in parallel
      wave_results = execute_wave(prepared_scheduler, graph, wave, results)
      
      # Merge the results
      Map.merge(results, wave_results)
    end)
    
    # Update partial results
    _scheduler = %{prepared_scheduler | partial_results: final_results}
    
    final_results
  end
  
  @impl true
  def get_partial_results(scheduler) do
    scheduler.partial_results
  end
  
  # Helper function to compute waves of nodes
  defp compute_waves(graph) do
    # Get all nodes and their dependencies
    nodes = EmberEx.XCS.Graph.get_nodes(graph)
    deps = EmberEx.XCS.Graph.get_dependencies(graph)
    
    # Initialize the remaining nodes and completed nodes
    remaining_nodes = MapSet.new(nodes)
    completed_nodes = MapSet.new()
    
    # Compute waves
    compute_waves_recursive(remaining_nodes, completed_nodes, deps, [])
  end
  
  # Recursive function to compute waves
  defp compute_waves_recursive(remaining_nodes, completed_nodes, deps, waves) do
    # Find nodes that can be executed in the current wave
    current_wave = find_executable_nodes(remaining_nodes, completed_nodes, deps)
    
    # If no nodes can be executed, we're done
    if Enum.empty?(current_wave) do
      if Enum.empty?(remaining_nodes) do
        # All nodes have been assigned to waves
        Enum.reverse(waves)
      else
        # There's a cycle in the graph
        Logger.error("Cycle detected in graph: #{inspect(remaining_nodes)}")
        raise "Cycle detected in graph"
      end
    else
      # Remove current wave nodes from the remaining nodes
      new_remaining = MapSet.difference(remaining_nodes, MapSet.new(current_wave))
      
      # Add current wave nodes to the completed nodes
      new_completed = MapSet.union(completed_nodes, MapSet.new(current_wave))
      
      # Recurse with the next wave
      compute_waves_recursive(new_remaining, new_completed, deps, [current_wave | waves])
    end
  end
  
  # Find nodes that can be executed in the current wave
  defp find_executable_nodes(remaining_nodes, completed_nodes, deps) do
    # A node can be executed if all its dependencies are in the completed nodes
    Enum.filter(MapSet.to_list(remaining_nodes), fn node ->
      # Get nodes that this node depends on
      node_deps = find_dependencies(node, deps)
      
      # Check if all dependencies are completed
      Enum.all?(node_deps, fn dep -> MapSet.member?(completed_nodes, dep) end)
    end)
  end
  
  # Find all dependencies of a node
  defp find_dependencies(node, deps) do
    # Collect all nodes that this node depends on
    Enum.flat_map(deps, fn {from, to_list} ->
      if Enum.member?(to_list, node) do
        [from]
      else
        []
      end
    end)
  end
  
  # Execute all nodes in a wave
  defp execute_wave(_scheduler, graph, wave, results) do
    # Create tasks for each node in the wave
    tasks = Enum.map(wave, fn node_id ->
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
