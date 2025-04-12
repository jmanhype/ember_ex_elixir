defmodule EmberEx.XCS.Graph.ExecutionGraph do
  @moduledoc """
  Represents an optimized execution graph for the JIT system.
  
  An execution graph contains nodes that represent computation units
  and edges that represent data dependencies between nodes.
  """
  
  @type node_id :: String.t() | atom()
  @type node_data :: map()
  @type edge :: {node_id, node_id}
  
  @type t :: %__MODULE__{
    nodes: %{optional(node_id) => node_data},
    edges: [edge],
    metadata: map()
  }
  
  defstruct nodes: %{},
            edges: [],
            metadata: %{}
  
  @doc """
  Creates a new empty execution graph.
  
  ## Parameters
  
  - opts: Graph options
    - `:metadata` - Additional metadata for the graph
  
  ## Returns
  
  A new empty execution graph
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    metadata = Keyword.get(opts, :metadata, %{})
    %__MODULE__{metadata: metadata}
  end
  
  @doc """
  Adds a node to the graph.
  
  ## Parameters
  
  - graph: The execution graph
  - data: Node data (must be a map)
  - id: Optional node ID (auto-generated if not provided)
  
  ## Returns
  
  {updated_graph, node_id}
  """
  @spec add_node(t(), node_data(), node_id() | nil) :: {t(), node_id()}
  def add_node(%__MODULE__{} = graph, data, id \\ nil) when is_map(data) do
    # Generate node ID if not provided
    node_id = id || generate_node_id(graph)
    
    # Add node to graph
    nodes = Map.put(graph.nodes, node_id, data)
    graph = %{graph | nodes: nodes}
    
    {graph, node_id}
  end
  
  @doc """
  Adds a node to the graph and returns only the updated graph.
  
  ## Parameters
  
  - graph: The execution graph
  - data: Node data (must be a map)
  - id: Optional node ID (auto-generated if not provided)
  
  ## Returns
  
  Updated graph
  """
  @spec add_node!(t(), node_data(), node_id() | nil) :: t()
  def add_node!(%__MODULE__{} = graph, data, id \\ nil) do
    {graph, _} = add_node(graph, data, id)
    graph
  end
  
  @doc """
  Adds an edge between two nodes.
  
  ## Parameters
  
  - graph: The execution graph
  - from: Source node ID
  - to: Target node ID
  
  ## Returns
  
  Updated graph
  """
  @spec add_edge(t(), node_id(), node_id()) :: t()
  def add_edge(%__MODULE__{} = graph, from, to) do
    # Add edge to graph
    edges = [{from, to} | graph.edges]
    %{graph | edges: edges}
  end
  
  @doc """
  Gets a node from the graph.
  
  ## Parameters
  
  - graph: The execution graph
  - id: Node ID
  
  ## Returns
  
  Node data if found, nil otherwise
  """
  @spec get_node(t(), node_id()) :: node_data() | nil
  def get_node(%__MODULE__{} = graph, id) do
    Map.get(graph.nodes, id)
  end
  
  @doc """
  Gets all outgoing edges from a node.
  
  ## Parameters
  
  - graph: The execution graph
  - id: Node ID
  
  ## Returns
  
  List of target node IDs
  """
  @spec get_outgoing_edges(t(), node_id()) :: [node_id()]
  def get_outgoing_edges(%__MODULE__{} = graph, id) do
    graph.edges
    |> Enum.filter(fn {from, _} -> from == id end)
    |> Enum.map(fn {_, to} -> to end)
  end
  
  @doc """
  Gets all incoming edges to a node.
  
  ## Parameters
  
  - graph: The execution graph
  - id: Node ID
  
  ## Returns
  
  List of source node IDs
  """
  @spec get_incoming_edges(t(), node_id()) :: [node_id()]
  def get_incoming_edges(%__MODULE__{} = graph, id) do
    graph.edges
    |> Enum.filter(fn {_, to} -> to == id end)
    |> Enum.map(fn {from, _} -> from end)
  end
  
  @doc """
  Merges two execution graphs.
  
  ## Parameters
  
  - graph1: First execution graph
  - graph2: Second execution graph
  
  ## Returns
  
  {merged_graph, node_id_mapping}
  
  Where node_id_mapping maps node IDs from graph2 to their new IDs in the merged graph
  """
  @spec merge_graphs(t(), t()) :: {t(), %{node_id() => node_id()}}
  def merge_graphs(%__MODULE__{} = graph1, %__MODULE__{} = graph2) do
    # Create a mapping of node IDs from graph2 to new IDs in the merged graph
    {node_mapping, merged_nodes} = 
      Enum.reduce(graph2.nodes, {%{}, graph1.nodes}, fn {id, data}, {mapping, nodes} ->
        # Generate a new node ID to avoid conflicts
        new_id = generate_node_id(%{nodes: nodes})
        
        # Update mapping and nodes
        mapping = Map.put(mapping, id, new_id)
        nodes = Map.put(nodes, new_id, data)
        
        {mapping, nodes}
      end)
    
    # Remap and add edges from graph2
    remapped_edges = 
      Enum.map(graph2.edges, fn {from, to} ->
        from_id = Map.get(node_mapping, from, from)
        to_id = Map.get(node_mapping, to, to)
        {from_id, to_id}
      end)
    
    merged_edges = graph1.edges ++ remapped_edges
    
    # Merge metadata
    merged_metadata = Map.merge(graph1.metadata, graph2.metadata)
    
    # Create merged graph
    merged_graph = %__MODULE__{
      nodes: merged_nodes,
      edges: merged_edges,
      metadata: merged_metadata
    }
    
    {merged_graph, node_mapping}
  end
  
  @doc """
  Performs topological sorting on the graph.
  
  ## Parameters
  
  - graph: The execution graph
  
  ## Returns
  
  List of node IDs in topological order
  
  ## Raises
  
  RuntimeError if the graph contains cycles
  """
  @spec topological_sort(t()) :: [node_id()]
  def topological_sort(%__MODULE__{} = graph) do
    # Kahn's algorithm for topological sorting
    
    # Calculate in-degree for each node
    in_degree = 
      Enum.reduce(graph.nodes, %{}, fn {id, _}, acc ->
        Map.put(acc, id, 0)
      end)
    
    in_degree = 
      Enum.reduce(graph.edges, in_degree, fn {_, to}, acc ->
        Map.update(acc, to, 1, &(&1 + 1))
      end)
    
    # Find nodes with in-degree 0
    queue = 
      Enum.filter(Map.keys(graph.nodes), fn id ->
        Map.get(in_degree, id, 0) == 0
      end)
    
    # Process nodes in topological order
    do_topological_sort(graph, queue, in_degree, [])
  end
  
  @doc """
  Groups nodes by level for parallel execution.
  
  ## Parameters
  
  - graph: The execution graph
  
  ## Returns
  
  List of lists of node IDs, where each inner list represents a level
  that can be executed in parallel
  """
  @spec group_by_level(t()) :: [[node_id()]]
  def group_by_level(%__MODULE__{} = graph) do
    # Get nodes in topological order
    sorted_nodes = topological_sort(graph)
    
    # Calculate the longest path to each node
    longest_paths = 
      Enum.reduce(sorted_nodes, %{}, fn node, paths ->
        # Get all incoming nodes
        incoming = get_incoming_edges(graph, node)
        
        if incoming == [] do
          # No incoming edges, this is a level 0 node
          Map.put(paths, node, 0)
        else
          # Find the maximum level of incoming nodes
          max_level = 
            incoming
            |> Enum.map(fn in_node -> Map.get(paths, in_node, 0) end)
            |> Enum.max(fn -> 0 end)
          
          # This node's level is one more than its highest dependency
          Map.put(paths, node, max_level + 1)
        end
      end)
    
    # Group nodes by their level
    max_level = 
      longest_paths
      |> Map.values()
      |> Enum.max(fn -> 0 end)
    
    Enum.map(0..max_level, fn level ->
      Enum.filter(sorted_nodes, fn node ->
        Map.get(longest_paths, node, 0) == level
      end)
    end)
  end
  
  # Private helper functions
  
  defp do_topological_sort(_graph, [], _in_degree, result) do
    # If we've processed all nodes, return the result
    Enum.reverse(result)
  end
  
  defp do_topological_sort(graph, queue, in_degree, result) do
    # Take a node from the queue
    [node | queue_rest] = queue
    
    # Get outgoing edges
    outgoing = get_outgoing_edges(graph, node)
    
    # Update in-degree and queue
    {queue_new, in_degree_new} = 
      Enum.reduce(outgoing, {queue_rest, in_degree}, fn out_node, {q, d} ->
        # Decrease in-degree of outgoing node
        d = Map.update!(d, out_node, &(&1 - 1))
        
        # If in-degree becomes 0, add to queue
        q = if Map.get(d, out_node) == 0, do: [out_node | q], else: q
        
        {q, d}
      end)
    
    # Add node to result
    do_topological_sort(graph, queue_new, in_degree_new, [node | result])
  end
  
  defp generate_node_id(graph) do
    # Generate a unique node ID
    id = "node_#{:erlang.unique_integer([:positive])}"
    
    # Ensure it doesn't conflict with existing nodes
    if Map.has_key?(graph.nodes, id) do
      generate_node_id(graph)
    else
      id
    end
  end
end
