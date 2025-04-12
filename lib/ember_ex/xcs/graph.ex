defmodule EmberEx.XCS.Graph do
  @moduledoc """
  A directed graph for representing computational workflows.
  
  The Graph module provides a data structure for representing computational
  graphs where nodes are operators and edges represent data dependencies.
  This enables complex workflows to be composed and executed efficiently.
  """
  
  @typedoc "Node ID type"
  @type node_id :: String.t()
  
  @typedoc "Node type"
  @type graph_node :: %{
    id: node_id(),
    operator: EmberEx.Operators.Operator.t(),
    metadata: map()
  }
  
  @typedoc "Edge type"
  @type edge :: %{
    from: node_id(),
    to: node_id(),
    from_output: String.t() | nil,
    to_input: String.t()
  }
  
  @typedoc "Graph type"
  @type t :: %__MODULE__{
    nodes: %{optional(node_id()) => graph_node()},
    edges: list(edge()),
    metadata: map()
  }
  
  defstruct nodes: %{}, edges: [], metadata: %{}
  
  @doc """
  Create a new empty graph.
  
  ## Parameters
  
  - metadata: Optional metadata for the graph
  
  ## Returns
  
  A new empty graph
  
  ## Examples
  
      iex> graph = EmberEx.XCS.Graph.new()
      iex> graph = EmberEx.XCS.Graph.new(%{name: "My Workflow"})
  """
  @spec new(map()) :: t()
  def new(metadata \\ %{}) do
    %__MODULE__{metadata: metadata}
  end
  
  @doc """
  Add a node to the graph.
  
  ## Parameters
  
  - graph: The graph to add the node to
  - id: The ID for the node
  - operator: The operator for the node
  - metadata: Optional metadata for the node
  
  ## Returns
  
  The updated graph
  
  ## Examples
  
      iex> graph = EmberEx.XCS.Graph.new()
      iex> graph = EmberEx.XCS.Graph.add_node(graph, "node1", my_operator)
  """
  @spec add_node(t(), node_id(), EmberEx.Operators.Operator.t(), map()) :: t()
  def add_node(graph, id, operator, metadata \\ %{}) do
    node = %{
      id: id,
      operator: operator,
      metadata: metadata
    }
    
    %{graph | nodes: Map.put(graph.nodes, id, node)}
  end
  
  @doc """
  Add an edge between two nodes in the graph.
  
  ## Parameters
  
  - graph: The graph to add the edge to
  - from: The ID of the source node
  - to: The ID of the target node
  - from_output: The output field of the source node (optional)
  - to_input: The input field of the target node
  
  ## Returns
  
  The updated graph
  
  ## Examples
  
      iex> graph = EmberEx.XCS.Graph.new()
      iex> graph = EmberEx.XCS.Graph.add_node(graph, "node1", op1)
      iex> graph = EmberEx.XCS.Graph.add_node(graph, "node2", op2)
      iex> graph = EmberEx.XCS.Graph.add_edge(graph, "node1", "node2", nil, "input")
  """
  @spec add_edge(t(), node_id(), node_id(), String.t() | nil, String.t()) :: t()
  def add_edge(graph, from, to, from_output \\ nil, to_input) do
    # Validate that the nodes exist
    unless Map.has_key?(graph.nodes, from) do
      raise "Source node '#{from}' does not exist in the graph"
    end
    
    unless Map.has_key?(graph.nodes, to) do
      raise "Target node '#{to}' does not exist in the graph"
    end
    
    # Create the edge
    edge = %{
      from: from,
      to: to,
      from_output: from_output,
      to_input: to_input
    }
    
    # Add the edge to the graph
    %{graph | edges: [edge | graph.edges]}
  end
  
  @doc """
  Get a node from the graph by ID.
  
  ## Parameters
  
  - graph: The graph to get the node from
  - id: The ID of the node to get
  
  ## Returns
  
  The node with the given ID
  
  ## Raises
  
  - KeyError: If the node does not exist
  """
  @spec get_node(t(), node_id()) :: graph_node()
  def get_node(graph, id) do
    Map.fetch!(graph.nodes, id)
  end
  
  @doc """
  Get all nodes in the graph.
  
  ## Parameters
  
  - graph: The graph to get nodes from
  
  ## Returns
  
  A list of node IDs
  """
  @spec get_nodes(t()) :: list(node_id())
  def get_nodes(graph) do
    Map.keys(graph.nodes)
  end
  
  @doc """
  Get all dependencies in the graph.
  
  ## Parameters
  
  - graph: The graph to get dependencies from
  
  ## Returns
  
  A map of node IDs to lists of dependent node IDs
  """
  @spec get_dependencies(t()) :: %{optional(node_id()) => list(node_id())}
  def get_dependencies(graph) do
    # Initialize the map with empty lists for all nodes
    deps = Enum.reduce(get_nodes(graph), %{}, fn node_id, acc ->
      Map.put(acc, node_id, [])
    end)
    
    # Add dependencies from edges
    Enum.reduce(graph.edges, deps, fn edge, acc ->
      Map.update(acc, edge.from, [edge.to], fn deps -> [edge.to | deps] end)
    end)
  end
  
  @doc """
  Get input dependencies for a node.
  
  ## Parameters
  
  - graph: The graph to get dependencies from
  - node_id: The ID of the node to get input dependencies for
  
  ## Returns
  
  A map of input field names to source node IDs
  """
  @spec get_input_dependencies(t(), node_id()) :: %{optional(String.t()) => node_id()}
  def get_input_dependencies(graph, node_id) do
    # Find all edges where the target is the given node
    Enum.filter(graph.edges, fn edge -> edge.to == node_id end)
    |> Enum.map(fn edge -> {edge.from, edge.to_input} end)
    |> Map.new()
  end
  
  @doc """
  Get output dependencies for a node.
  
  ## Parameters
  
  - graph: The graph to get dependencies from
  - node_id: The ID of the node to get output dependencies for
  
  ## Returns
  
  A list of {target_node_id, input_field} tuples
  """
  @spec get_output_dependencies(t(), node_id()) :: list({node_id(), String.t()})
  def get_output_dependencies(graph, node_id) do
    # Find all edges where the source is the given node
    Enum.filter(graph.edges, fn edge -> edge.from == node_id end)
    |> Enum.map(fn edge -> {edge.to, edge.to_input} end)
  end
  
  @doc """
  Get input nodes for the graph.
  
  Input nodes are nodes that have no incoming edges.
  
  ## Parameters
  
  - graph: The graph to get input nodes from
  
  ## Returns
  
  A list of input node IDs
  """
  @spec get_input_nodes(t()) :: list(node_id())
  def get_input_nodes(graph) do
    # Get all nodes that are targets in edges
    targets = Enum.map(graph.edges, fn edge -> edge.to end)
    |> MapSet.new()
    
    # Get all nodes that are not targets
    get_nodes(graph)
    |> Enum.filter(fn node_id -> not MapSet.member?(targets, node_id) end)
  end
  
  @doc """
  Get output nodes for the graph.
  
  Output nodes are nodes that have no outgoing edges.
  
  ## Parameters
  
  - graph: The graph to get output nodes from
  
  ## Returns
  
  A list of output node IDs
  """
  @spec get_output_nodes(t()) :: list(node_id())
  def get_output_nodes(graph) do
    # Get all nodes that are sources in edges
    sources = Enum.map(graph.edges, fn edge -> edge.from end)
    |> MapSet.new()
    
    # Get all nodes that are not sources
    get_nodes(graph)
    |> Enum.filter(fn node_id -> not MapSet.member?(sources, node_id) end)
  end
  
  @doc """
  Convert a sequence of operators to a graph.
  
  ## Parameters
  
  - operators: A list of operators to convert
  - metadata: Optional metadata for the graph
  
  ## Returns
  
  A new graph representing the sequence
  
  ## Examples
  
      iex> graph = EmberEx.XCS.Graph.from_sequence([op1, op2, op3])
  """
  @spec from_sequence(list(EmberEx.Operators.Operator.t()), map()) :: t()
  def from_sequence(operators, metadata \\ %{}) do
    # Create a new graph
    graph = new(metadata)
    
    # Add nodes for each operator
    {graph, _} = Enum.reduce(operators, {graph, 0}, fn operator, {graph, index} ->
      node_id = "node_#{index}"
      graph = add_node(graph, node_id, operator)
      {graph, index + 1}
    end)
    
    # Add edges between nodes
    {graph, _} = Enum.reduce(1..(length(operators) - 1), {graph, 0}, fn index, {graph, prev_index} ->
      from = "node_#{prev_index}"
      to = "node_#{index}"
      graph = add_edge(graph, from, to, nil, "input")
      {graph, index}
    end)
    
    graph
  end
  
  @doc """
  Execute the graph with the given inputs.
  
  ## Parameters
  
  - graph: The graph to execute
  - inputs: Input values for the graph's input nodes
  - scheduler_type: The type of scheduler to use (default: "auto")
  - scheduler_opts: Options for the scheduler
  
  ## Returns
  
  A map of node IDs to their output values
  
  ## Examples
  
      iex> results = EmberEx.XCS.Graph.execute(graph, %{"node1" => %{text: "Hello"}})
  """
  @spec execute(t(), map(), String.t(), keyword()) :: map()
  def execute(graph, inputs, scheduler_type \\ "auto", scheduler_opts \\ []) do
    # Create a scheduler
    scheduler = EmberEx.XCS.Schedulers.BaseScheduler.create(scheduler_type, scheduler_opts)
    
    # Prepare the scheduler
    scheduler = EmberEx.XCS.Schedulers.BaseScheduler.prepare(scheduler, graph)
    
    # Execute the graph
    EmberEx.XCS.Schedulers.BaseScheduler.execute(scheduler, graph, inputs)
  end
end
