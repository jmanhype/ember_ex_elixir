defmodule EmberEx.XCS.Graph.EnhancedGraphBuilder do
  @moduledoc """
  Builds optimization graphs using a hybrid of structural and trace-based approaches.
  
  This builder combines the benefits of both static structural analysis and
  dynamic execution tracing to create maximally optimized execution graphs.
  """
  
  require Logger
  alias EmberEx.XCS.Graph.ExecutionGraph
  alias EmberEx.XCS.Graph.StructuralGraphBuilder
  alias EmberEx.XCS.Graph.TraceGraphBuilder
  
  @type t :: %__MODULE__{
    structural_builder: StructuralGraphBuilder.t(),
    trace_builder: TraceGraphBuilder.t(),
    recursive: boolean()
  }
  
  defstruct [
    structural_builder: nil,
    trace_builder: nil,
    recursive: true
  ]
  
  @doc """
  Creates a new enhanced graph builder.
  
  ## Parameters
  
  - opts: Options for the graph builder
    - `:recursive` - Whether to recursively analyze nested operators
  
  ## Returns
  
  A new EnhancedGraphBuilder struct
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    recursive = Keyword.get(opts, :recursive, true)
    
    %__MODULE__{
      structural_builder: StructuralGraphBuilder.new(recursive: recursive),
      trace_builder: TraceGraphBuilder.new(),
      recursive: recursive
    }
  end
  
  @doc """
  Builds an execution graph from an operator or function with specific inputs.
  
  ## Parameters
  
  - target: Target operator or function to analyze
  - inputs: Input values for execution
  - opts: Additional options
    - `:recursive` - Whether to recursively analyze nested operators
  
  ## Returns
  
  {execution_result, optimized_graph}
  """
  @spec build_graph(function() | module(), map(), keyword()) :: {term(), ExecutionGraph.t()}
  def build_graph(target, inputs, opts \\ []) do
    recursive = Keyword.get(opts, :recursive, true)
    builder = new(recursive: recursive)
    
    # Phase 1: Perform structural analysis
    structural_graph = StructuralGraphBuilder.build_graph(builder.structural_builder, target)
    
    # Phase 2: Trace execution to capture actual execution path
    {result, trace} = TraceGraphBuilder.trace_execution(target, inputs)
    trace_graph = TraceGraphBuilder.build_graph_from_trace(trace)
    
    # Phase 3: Merge the graphs with precedence to trace-based optimizations
    optimized_graph = merge_and_optimize_graphs(structural_graph, trace_graph, target, inputs)
    
    {result, optimized_graph}
  end
  
  # Private helper functions
  
  defp merge_and_optimize_graphs(structural_graph, trace_graph, target, inputs) do
    # Strategy for merging:
    # 1. Start with the structural graph as a base (static analysis)
    # 2. For paths that were actually executed in the trace, use the trace graph (dynamic analysis)
    # 3. For paths not executed, keep the structural analysis
    
    # Create a new graph that will hold the merged result
    merged_graph = ExecutionGraph.new(
      metadata: %{
        optimization_type: :enhanced,
        target: inspect(target),
        input_signature: :erlang.phash2(inputs),
        timestamp: :os.system_time(:second)
      }
    )
    
    # If trace graph has execution data, prioritize it
    if map_size(trace_graph.nodes) > 0 do
      # The trace graph already captured the execution path, use it as primary
      {merged_graph, _} = ExecutionGraph.merge_graphs(merged_graph, trace_graph)
      
      # Add structural nodes that aren't in the trace for completeness
      structural_graph.nodes
      |> Enum.filter(fn {_id, node} -> 
        # Only include nodes that don't overlap with trace
        not Enum.any?(trace_graph.nodes, fn {_, trace_node} ->
          nodes_equivalent?(node, trace_node)
        end)
      end)
      |> Enum.reduce(merged_graph, fn {_, node}, graph ->
        ExecutionGraph.add_node!(graph, Map.put(node, :source, :structural))
      end)
      
      # Add metadata about the merge
      metadata = Map.merge(merged_graph.metadata, %{
        primary_source: :trace,
        structural_nodes: map_size(structural_graph.nodes),
        trace_nodes: map_size(trace_graph.nodes)
      })
      
      %{merged_graph | metadata: metadata}
    else
      # Trace didn't capture useful data, fall back to structural
      {merged_graph, _} = ExecutionGraph.merge_graphs(merged_graph, structural_graph)
      
      # Add metadata
      metadata = Map.merge(merged_graph.metadata, %{
        primary_source: :structural,
        structural_nodes: map_size(structural_graph.nodes),
        trace_nodes: 0
      })
      
      %{merged_graph | metadata: metadata}
    end
  end
  
  defp nodes_equivalent?(node1, node2) do
    # Check if two nodes represent the same logical operation
    # This is used to avoid duplication when merging graphs
    
    cond do
      # For function nodes, compare the function references
      node1[:type] == :function and node2[:type] == :function ->
        function_equivalent?(node1[:function], node2[:function])
        
      # For operator nodes, compare module names
      node1[:type] == :operator and node2[:type] == :operator ->
        node1[:module] == node2[:module]
        
      # For other node types, compare the full node data
      true ->
        Map.drop(node1, [:name, :id]) == Map.drop(node2, [:name, :id])
    end
  end
  
  defp function_equivalent?(func1, func2) when is_function(func1) and is_function(func2) do
    # Compare function identity
    info1 = :erlang.fun_info(func1)
    info2 = :erlang.fun_info(func2)
    
    info1[:module] == info2[:module] and
    info1[:name] == info2[:name] and
    info1[:arity] == info2[:arity]
  end
  
  defp function_equivalent?(_, _), do: false
end
