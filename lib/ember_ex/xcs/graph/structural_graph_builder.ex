defmodule EmberEx.XCS.Graph.StructuralGraphBuilder do
  @moduledoc """
  Builds optimization graphs by analyzing operator structure.
  
  This builder analyzes operator and function structure to identify
  optimization opportunities without executing the code.
  """
  
  require Logger
  alias EmberEx.XCS.Graph.ExecutionGraph
  
  @type t :: %__MODULE__{
    recursive: boolean()
  }
  
  defstruct recursive: true
  
  @doc """
  Creates a new structural graph builder.
  
  ## Parameters
  
  - opts: Options for the graph builder
    - `:recursive` - Whether to recursively analyze nested operators
  
  ## Returns
  
  A new StructuralGraphBuilder struct
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    recursive = Keyword.get(opts, :recursive, true)
    %__MODULE__{recursive: recursive}
  end
  
  @doc """
  Builds an execution graph from an operator or function.
  
  ## Parameters
  
  - builder: The graph builder
  - target: Target operator or function to analyze
  
  ## Returns
  
  An execution graph optimized based on structural analysis
  """
  @spec build_graph(t(), function() | module()) :: ExecutionGraph.t()
  def build_graph(%__MODULE__{} = builder, target) do
    # Start building the graph
    Logger.debug("Building structural graph for #{inspect(target)}")
    
    # Create a new execution graph
    graph = ExecutionGraph.new()
    
    # Analyze the target based on its type
    cond do
      is_atom(target) and function_exported?(target, :forward, 1) ->
        build_operator_graph(builder, target, graph)
        
      is_atom(target) and function_exported?(target, :call, 1) ->
        build_function_graph(builder, &target.call/1, graph)
        
      is_function(target) ->
        build_function_graph(builder, target, graph)
        
      true ->
        # Fallback for unsupported targets
        Logger.warning("Unsupported target type for structural analysis: #{inspect(target)}")
        build_passthrough_graph(target, graph)
    end
  end
  
  # Private helper functions
  
  defp build_operator_graph(builder, operator_module, graph) do
    # For operators, we need to check if they expose their structure
    if function_exported?(operator_module, :get_structure, 0) do
      # Operator exposes its structure directly
      structure = operator_module.get_structure()
      build_graph_from_structure(builder, structure, graph)
    else
      # Try to infer structure from attributes and fields
      infer_operator_structure(builder, operator_module, graph)
    end
  end
  
  defp build_function_graph(_builder, function, graph) do
    # For plain functions, we just add a single node that executes the function
    node_id = ExecutionGraph.add_node(graph, %{
      type: :function,
      function: function,
      name: function_name(function)
    })
    
    # Connect the node to inputs and outputs
    ExecutionGraph.add_edge(graph, :input, node_id)
    ExecutionGraph.add_edge(graph, node_id, :output)
    
    graph
  end
  
  defp build_passthrough_graph(target, graph) do
    # Create a passthrough graph that just calls the target
    node_id = ExecutionGraph.add_node(graph, %{
      type: :passthrough,
      target: target,
      name: "passthrough_#{:erlang.phash2(target)}"
    })
    
    # Connect the node to inputs and outputs
    ExecutionGraph.add_edge(graph, :input, node_id)
    ExecutionGraph.add_edge(graph, node_id, :output)
    
    graph
  end
  
  defp build_graph_from_structure(builder, structure, graph) do
    case structure do
      %{type: :sequence, operators: operators} ->
        build_sequence_graph(builder, operators, graph)
        
      %{type: :parallel, operators: operators} ->
        build_parallel_graph(builder, operators, graph)
        
      %{type: :map, function: func} ->
        build_function_graph(builder, func, graph)
        
      %{type: :llm, prompt_template: _template} ->
        # For LLM operators, we don't optimize further
        build_passthrough_graph(structure, graph)
        
      _ ->
        # Fallback for unknown structures
        build_passthrough_graph(structure, graph)
    end
  end
  
  defp build_sequence_graph(builder, operators, graph) do
    # Build a graph with operators connected in sequence
    prev_node_id = :input
    graph_ref = graph
    
    {final_graph, final_prev} = Enum.reduce(operators, {graph_ref, prev_node_id}, fn operator, {acc_graph, prev_id} ->
      # Build graph for this operator
      operator_graph = build_graph(builder, operator)
      
      # Merge operator graph into main graph
      {merged_graph, node_map} = ExecutionGraph.merge_graphs(acc_graph, operator_graph)
      
      # Connect this operator to the previous one
      input_node = Map.get(node_map, :input)
      output_node = Map.get(node_map, :output)
      
      updated_graph = ExecutionGraph.add_edge(merged_graph, prev_id, input_node)
      
      # Return updated graph and prev_id for next iteration
      {updated_graph, output_node}
    end)
    
    # Connect the last operator to the output
    final_result = ExecutionGraph.add_edge(final_graph, final_prev, :output)
    
    final_result
  end
  
  defp build_parallel_graph(builder, operators, graph) do
    # Build a graph with operators executed in parallel
    Enum.each(operators, fn operator ->
      # Build graph for this operator
      operator_graph = build_graph(builder, operator)
      
      # Merge operator graph into main graph
      {graph, node_map} = ExecutionGraph.merge_graphs(graph, operator_graph)
      
      # Connect this operator to the input and output
      input_node = Map.get(node_map, :input)
      output_node = Map.get(node_map, :output)
      
      ExecutionGraph.add_edge(graph, :input, input_node)
      ExecutionGraph.add_edge(graph, output_node, :output)
    end)
    
    graph
  end
  
  defp infer_operator_structure(builder, operator_module, graph) do
    # Try to infer the structure from module attributes and operators
    operators = extract_nested_operators(operator_module)
    
    if builder.recursive and operators != [] do
      # If we found nested operators, build a composite graph
      if length(operators) > 1 do
        # Multiple operators might indicate parallel execution
        build_parallel_graph(builder, operators, graph)
      else
        # Single operator suggests sequential execution
        build_sequence_graph(builder, operators, graph)
      end
    else
      # No nested operators or non-recursive mode, create a simple passthrough
      build_passthrough_graph(operator_module, graph)
    end
  end
  
  defp extract_nested_operators(module) when is_atom(module) do
    # Try to extract nested operators from module attributes
    if Code.ensure_loaded?(module) do
      # Check for attributes that might contain operators
      attrs = module.__info__(:attributes)
      
      # Look for operator fields (based on naming patterns)
      Enum.flat_map(attrs, fn {key, values} ->
        if is_atom(key) and 
           (to_string(key) =~ ~r/operator/i or to_string(key) =~ ~r/op_/) do
          # Extract operator modules from attribute values
          Enum.flat_map(values, fn value ->
            cond do
              is_atom(value) and Code.ensure_loaded?(value) and 
              (function_exported?(value, :forward, 1) or function_exported?(value, :call, 1)) ->
                [value]
              is_list(value) ->
                # Try to extract operators from lists
                Enum.filter(value, fn v ->
                  is_atom(v) and Code.ensure_loaded?(v) and 
                  (function_exported?(v, :forward, 1) or function_exported?(v, :call, 1))
                end)
              true ->
                []
            end
          end)
        else
          []
        end
      end)
    else
      []
    end
  end
  
  defp function_name(function) when is_function(function) do
    # Try to get a meaningful name for the function
    info = :erlang.fun_info(function)
    
    cond do
      info[:name] != :"-" ->
        # Named function
        "#{info[:module]}.#{info[:name]}/#{info[:arity]}"
      true ->
        # Anonymous function
        "anonymous_#{info[:unique_integer]}"
    end
  end
end
