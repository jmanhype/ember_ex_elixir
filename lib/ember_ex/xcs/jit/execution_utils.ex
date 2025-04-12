defmodule EmberEx.XCS.JIT.ExecutionUtils do
  @moduledoc """
  Utilities for executing JIT-compiled graphs.
  
  Provides functions for executing optimized execution graphs
  with proper metrics tracking and error handling.
  """
  
  alias EmberEx.XCS.JIT.Cache
  alias EmberEx.XCS.JIT.LLMDetector
  require Logger
  
  @doc """
  Executes a compiled execution graph with the given inputs.
  
  ## Parameters
  
  - graph: The compiled execution graph to execute
  - inputs: Input values for the execution
  - original: The original function or operator (for metrics)
  
  ## Returns
  
  The result of the graph execution
  
  ## Raises
  
  - Any error that occurs during execution
  """
  @spec execute_compiled_graph(term(), map(), function() | module()) :: term()
  def execute_compiled_graph(graph, inputs, original) do
    execution_start = :os.system_time(:millisecond) / 1000
    
    # Record cache hit
    Cache.record_cache_hit(original)
    
    # Execute the graph using the XCS execution engine
    result = execute_graph(graph, inputs)
    
    execution_duration = :os.system_time(:millisecond) / 1000 - execution_start
    Cache.record_execution(original, execution_duration)
    
    result
  end
  
  @doc """
  Executes a graph based on its type.
  
  Different graph types require different execution methods.
  
  ## Parameters
  
  - graph: The graph to execute
  - inputs: Input values for the execution
  
  ## Returns
  
  The result of the graph execution
  """
  @spec execute_graph(term(), map()) :: term()
  def execute_graph(graph, inputs) do
    case graph do
      %{__struct__: EmberEx.XCS.Graph.ExecutionGraph} = exec_graph ->
        # Execute using the XCS execution engine
        EmberEx.XCS.Engine.execute(exec_graph, inputs)
        
      %{type: :function, function: func} when is_function(func) ->
        # Execute a plain function
        func.(inputs)
        
      %{type: :operator, module: module} when is_atom(module) ->
        # Execute a module-based operator
        module.call(inputs)
        
      %{nodes: nodes, edges: edges} when is_map(nodes) and is_list(edges) ->
        # Execute a plain graph structure
        EmberEx.XCS.Engine.execute_raw_graph(%{nodes: nodes, edges: edges}, inputs)
      
      # Handle LLM specialized graph structure with root, nodes, and metadata
      %{root: root, nodes: nodes, edges: edges, metadata: metadata} when is_map(root) ->
        # Execute an LLM specialized graph
        execute_llm_graph(root, nodes, edges, metadata, inputs)
        
      func when is_function(func) ->
        # Direct function execution
        func.(inputs)
        
      _ ->
        # Fallback for unknown graph types
        raise "Unknown graph type: #{inspect(graph)}"
    end
  end
  
  @doc """
  Executes an LLM specialized graph with optimized handling of LLM operations.
  
  ## Parameters
  
  - root: The root node of the graph
  - nodes: The nodes in the graph
  - edges: The edges connecting nodes
  - metadata: Graph metadata including optimization settings
  - inputs: Input values for execution
  
  ## Returns
  
  The result of the graph execution
  """
  @spec execute_llm_graph(map(), list(), list(), map(), map()) :: term()
  def execute_llm_graph(root, nodes, edges, _metadata, inputs) do
    # Extract important information from root node
    target = root.target
    is_llm = Map.get(root, :is_llm, false)
    preserve_stochasticity = Map.get(root, :preserve_stochasticity, true)
    
    # For nodes marked as LLM operations or with stochasticity preserved,
    # bypass optimization and call the original function
    if is_llm && preserve_stochasticity do
      Logger.debug("Executing LLM node with preserved stochasticity: #{inspect(target)}")
      execute_original(target, inputs)
    else
      # For non-LLM nodes or those where optimization is allowed,
      # execute according to the graph structure
      case nodes do
        [] -> 
          # If no child nodes, just execute the target
          execute_original(target, inputs)
          
        _ ->
          # Create a mini execution plan for this subgraph
          # This would integrate with a more sophisticated execution engine
          # in a full implementation
          execute_llm_subgraph(root, nodes, edges, inputs)
      end
    end
  end
  
  @doc """
  Executes a subgraph within an LLM specialized graph.
  
  This is a simplified implementation that would be replaced with a more
  sophisticated execution engine in a production system.
  
  ## Parameters
  
  - root: The root node of the subgraph
  - nodes: The nodes in the subgraph
  - edges: The edges connecting nodes
  - inputs: Input values for execution
  
  ## Returns
  
  The result of the subgraph execution
  """
  @spec execute_llm_subgraph(map(), list(), list(), map()) :: term()
  def execute_llm_subgraph(root, _nodes, _edges, inputs) do
    # In a full implementation, this would traverse the graph and execute
    # nodes in topological order. For now, we'll just execute the root.
    execute_original(root.target, inputs)
  end
  
  @doc """
  Executes the original target (function or operator).
  
  ## Parameters
  
  - target: The original function or operator
  - inputs: Input values for execution
  
  ## Returns
  
  The result of executing the target
  """
  @spec execute_original(term(), map()) :: term()
  def execute_original(target, inputs) do
    cond do
      is_function(target) ->
        # Execute function
        target.(inputs)
        
      is_atom(target) && function_exported?(target, :call, 1) ->
        # Execute module-based operator
        target.call(inputs)
        
      is_map(target) && Map.has_key?(target, :__struct__) ->
        # Execute struct-based operator through the Operator protocol
        EmberEx.Operators.Operator.call(target, inputs)
        
      true ->
        raise "Cannot execute target: #{inspect(target)}"
    end
  end
end
