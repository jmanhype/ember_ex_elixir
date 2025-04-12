defmodule EmberEx.XCS.Graph.TraceGraphBuilder do
  @moduledoc """
  Builds optimization graphs by tracing operator execution.
  
  This builder analyzes the actual execution path taken by an operator with
  specific inputs to generate an optimized graph for similar future inputs.
  """
  
  require Logger
  alias EmberEx.XCS.Graph.ExecutionGraph
  
  @type execution_trace :: [map()]
  @type t :: %__MODULE__{}
  
  defstruct []
  
  @doc """
  Creates a new trace graph builder.
  
  ## Returns
  
  A new TraceGraphBuilder struct
  """
  @spec new() :: t()
  def new do
    %__MODULE__{}
  end
  
  @doc """
  Traces the execution of a function or operator with given inputs.
  
  ## Parameters
  
  - target: Function or operator to trace
  - inputs: Input values for execution
  
  ## Returns
  
  {result, execution_trace} - The execution result and captured trace
  """
  @spec trace_execution(function() | module(), map()) :: {term(), execution_trace()}
  def trace_execution(target, inputs) do
    # Set up tracing
    trace_id = "trace_#{:erlang.unique_integer([:positive])}"
    Process.put({:ember_ex_trace, trace_id}, [])
    
    # Create trace wrapper
    wrap_with_trace = fn func ->
      fn inputs ->
        # Record function call in trace
        trace_entry = %{
          type: :function_call,
          function: func,
          inputs: inputs,
          timestamp: :os.system_time(:microsecond)
        }
        
        current_trace = Process.get({:ember_ex_trace, trace_id}, [])
        Process.put({:ember_ex_trace, trace_id}, [trace_entry | current_trace])
        
        # Execute function
        result = func.(inputs)
        
        # Record function return in trace
        trace_entry = %{
          type: :function_return,
          function: func,
          result: result,
          timestamp: :os.system_time(:microsecond)
        }
        
        current_trace = Process.get({:ember_ex_trace, trace_id}, [])
        Process.put({:ember_ex_trace, trace_id}, [trace_entry | current_trace])
        
        result
      end
    end
    
    # Execute with tracing based on target type
    result = cond do
      is_function(target) ->
        wrapped = wrap_with_trace.(target)
        wrapped.(inputs)
        
      is_atom(target) && Code.ensure_loaded?(target) && function_exported?(target, :call, 1) ->
        # For module-based operators
        wrapped = wrap_with_trace.(fn inp -> target.call(inp) end)
        wrapped.(inputs)
        
      is_atom(target) && Code.ensure_loaded?(target) && function_exported?(target, :forward, 1) ->
        # For operator modules with forward
        wrapped = wrap_with_trace.(fn inp -> target.forward(inp) end)
        wrapped.(inputs)
        
      true ->
        raise "Unsupported target type for tracing: #{inspect(target)}"
    end
    
    # Get accumulated trace
    trace = Process.get({:ember_ex_trace, trace_id}, [])
    
    # Clean up trace data
    Process.delete({:ember_ex_trace, trace_id})
    
    # Return the result and execution trace (reversed to get chronological order)
    {result, Enum.reverse(trace)}
  end
  
  @doc """
  Builds an execution graph from a captured execution trace.
  
  ## Parameters
  
  - trace: Execution trace captured by trace_execution
  
  ## Returns
  
  An execution graph optimized based on the traced execution path
  """
  @spec build_graph_from_trace(execution_trace()) :: ExecutionGraph.t()
  def build_graph_from_trace(trace) do
    # Create a new execution graph
    graph = ExecutionGraph.new()
    
    # Build graph from trace entries
    {graph, _node_map} = build_nodes_from_trace(trace, graph, %{})
    
    # Add metadata about the trace
    trace_metadata = %{
      trace_size: length(trace),
      trace_timestamp: :os.system_time(:second)
    }
    
    %{graph | metadata: Map.merge(graph.metadata, trace_metadata)}
  end
  
  # Private helper functions
  
  defp build_nodes_from_trace([], graph, node_map) do
    # No more trace entries, return the graph
    {graph, node_map}
  end
  
  defp build_nodes_from_trace([trace_entry | rest], graph, node_map) do
    # Process trace entry based on its type
    case trace_entry do
      %{type: :function_call, function: func, inputs: inputs} ->
        # Generate a unique ID for this function call
        call_id = "call_#{:erlang.phash2({func, inputs})}"
        
        # Add node to graph if not already present
        {graph, node_id} = if Map.has_key?(node_map, call_id) do
          {graph, Map.get(node_map, call_id)}
        else
          # Create a new node for this function call
          {graph, node_id} = ExecutionGraph.add_node(graph, %{
            type: :function,
            function: func,
            name: function_name(func),
            inputs_pattern: extract_pattern(inputs)
          })
          
          {graph, node_id}
        end
        
        # Update node map
        node_map = Map.put(node_map, call_id, node_id)
        
        # Process rest of trace
        build_nodes_from_trace(rest, graph, node_map)
        
      %{type: :function_return, function: func, result: result} ->
        # Get the node for this function
        call_id = "call_#{:erlang.phash2({func, :_})}"
        
        if Map.has_key?(node_map, call_id) do
          # Get the node ID
          node_id = Map.get(node_map, call_id)
          
          # Update node with result information
          node_data = ExecutionGraph.get_node(graph, node_id)
          updated_node = Map.merge(node_data, %{
            result_pattern: extract_pattern(result)
          })
          
          # Update graph with modified node
          nodes = Map.put(graph.nodes, node_id, updated_node)
          graph = %{graph | nodes: nodes}
          
          # Process rest of trace
          build_nodes_from_trace(rest, graph, node_map)
        else
          # This is unexpected, but continue processing
          Logger.warning("Found function return without matching call: #{inspect(func)}")
          build_nodes_from_trace(rest, graph, node_map)
        end
        
      _ ->
        # Unknown trace entry type, skip it
        build_nodes_from_trace(rest, graph, node_map)
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
  
  defp function_name(other) do
    "unknown_#{:erlang.phash2(other)}"
  end
  
  defp extract_pattern(value) do
    # Extract a pattern representation of the value
    # This is used for input and output pattern matching
    case value do
      v when is_map(v) ->
        # For maps, keep keys but extract patterns for values
        Enum.into(v, %{}, fn {k, v} -> {k, extract_pattern(v)} end)
        
      v when is_list(v) ->
        # For lists, extract patterns for each element
        Enum.map(v, &extract_pattern/1)
        
      v when is_tuple(v) ->
        # For tuples, convert to list, extract patterns, then back to tuple
        v
        |> Tuple.to_list()
        |> Enum.map(&extract_pattern/1)
        |> List.to_tuple()
        
      # For atoms, numbers, and other simple values, use as is
      v when is_atom(v) or is_number(v) or is_binary(v) ->
        v
        
      # For complex values, use a placeholder
      _ ->
        :complex_value
    end
  end
end
