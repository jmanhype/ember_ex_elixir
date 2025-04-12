defmodule EmberEx.XCS.Engine do
  @moduledoc """
  Execution engine for EmberEx XCS graphs.
  
  Provides the runtime execution environment for compiled execution graphs,
  supporting both sequential and parallel execution modes.
  """
  
  require Logger
  alias EmberEx.XCS.Graph.ExecutionGraph
  
  @doc """
  Executes a compiled execution graph with the given inputs.
  
  ## Parameters
  
  - graph: The compiled execution graph to execute
  - inputs: Input values for the execution
  
  ## Returns
  
  The result of the graph execution
  
  ## Raises
  
  - Any error that occurs during execution
  """
  @spec execute(ExecutionGraph.t(), map()) :: term()
  def execute(%ExecutionGraph{} = graph, inputs) when is_map(inputs) do
    # Group nodes by level for potentially parallel execution
    levels = ExecutionGraph.group_by_level(graph)
    
    # Start with input values
    node_results = %{input: inputs}
    
    # Execute levels in sequence
    Enum.reduce(levels, node_results, fn level, results ->
      # Execute all nodes in this level (potentially in parallel)
      level_results = execute_level(graph, level, results)
      
      # Merge results
      Map.merge(results, level_results)
    end)
    |> Map.get(:output)  # Return the final output
  end
  
  @doc """
  Executes a raw graph structure.
  
  ## Parameters
  
  - graph: Raw graph structure with nodes and edges
  - inputs: Input values for the execution
  
  ## Returns
  
  The result of the graph execution
  """
  @spec execute_raw_graph(map(), map()) :: term()
  def execute_raw_graph(%{nodes: nodes, edges: edges}, inputs) when is_map(inputs) do
    # Convert raw graph to ExecutionGraph
    graph = %ExecutionGraph{
      nodes: nodes,
      edges: edges,
      metadata: %{source: :raw_graph}
    }
    
    # Execute using the standard engine
    execute(graph, inputs)
  end
  
  # Private helper functions
  
  defp execute_level(graph, level, results) do
    # For now, execute nodes sequentially
    # In a future optimization, this could use Task.async_stream for parallelism
    Enum.reduce(level, %{}, fn node_id, level_results ->
      # Skip special nodes
      if node_id in [:input, :output] do
        level_results
      else
        # Get node data
        node_data = ExecutionGraph.get_node(graph, node_id)
        
        # Get input values for this node
        node_inputs = prepare_node_inputs(graph, node_id, results)
        
        # Execute node
        result = execute_node(node_data, node_inputs)
        
        # Store result
        Map.put(level_results, node_id, result)
      end
    end)
  end
  
  defp prepare_node_inputs(graph, node_id, results) do
    # Get incoming edges
    incoming = ExecutionGraph.get_incoming_edges(graph, node_id)
    
    # Special case for output node
    if node_id == :output and length(incoming) == 1 do
      # For output node, return the value from its single input
      source = hd(incoming)
      Map.get(results, source)
    else
      # For regular nodes, construct inputs map from incoming edges
      Enum.reduce(incoming, %{}, fn source, inputs ->
        # If source is :input, use the original inputs
        if source == :input do
          Map.merge(inputs, Map.get(results, :input, %{}))
        else
          # Get source node result
          source_result = Map.get(results, source)
          
          # If source_result is a map, merge it with inputs
          if is_map(source_result) do
            Map.merge(inputs, source_result)
          else
            # Otherwise use a default key based on source name
            source_key = "#{source}_output"
            Map.put(inputs, source_key, source_result)
          end
        end
      end)
    end
  end
  
  defp execute_node(node_data, inputs) do
    case node_data do
      %{type: :function, function: func} when is_function(func) ->
        # Execute function directly
        func.(inputs)
        
      %{type: :operator, module: module} when is_atom(module) ->
        # Execute module-based operator
        if function_exported?(module, :call, 1) do
          module.call(inputs)
        else
          raise "Operator module #{inspect(module)} does not implement call/1"
        end
        
      %{type: :passthrough, target: target} ->
        # Execute target based on its type
        cond do
          is_function(target) ->
            target.(inputs)
            
          is_atom(target) and function_exported?(target, :call, 1) ->
            target.call(inputs)
            
          is_atom(target) and function_exported?(target, :forward, 1) ->
            target.forward(inputs)
            
          true ->
            raise "Unsupported passthrough target: #{inspect(target)}"
        end
        
      _ ->
        # Unknown node type
        raise "Unknown node type: #{inspect(node_data)}"
    end
  end
end
