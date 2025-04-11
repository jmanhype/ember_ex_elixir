defmodule EmberEx.XCS.Schedulers.BaseScheduler do
  @moduledoc """
  Base behavior for XCS execution schedulers.
  
  Schedulers are responsible for determining the execution order and parallelization
  strategy for nodes in an XCS graph. Different schedulers optimize for different
  execution patterns and resource utilization.
  """
  
  @typedoc "XCS Graph type"
  @type graph :: EmberEx.XCS.Graph.t()
  
  @typedoc "Node ID type"
  @type node_id :: String.t()
  
  @typedoc "Input values type"
  @type inputs :: %{optional(node_id()) => map()}
  
  @typedoc "Output values type"
  @type outputs :: %{optional(node_id()) => map()}
  
  @doc """
  Prepare the scheduler for execution with the given graph.
  
  This function analyzes the graph structure and prepares any internal
  data structures needed for efficient execution.
  
  ## Parameters
  
  - scheduler: The scheduler struct
  - graph: The XCS graph to prepare for execution
  
  ## Returns
  
  The prepared scheduler struct
  """
  @callback prepare(scheduler :: struct(), graph :: graph()) :: struct()
  
  @doc """
  Execute the graph with the given inputs.
  
  This function executes all nodes in the graph according to the scheduler's
  strategy, respecting dependencies and maximizing parallelism where possible.
  
  ## Parameters
  
  - scheduler: The scheduler struct
  - graph: The XCS graph to execute
  - inputs: Input values for the graph's input nodes
  
  ## Returns
  
  A map of node IDs to their output values
  """
  @callback execute(scheduler :: struct(), graph :: graph(), inputs :: inputs()) :: outputs()
  
  @doc """
  Get partial results from the graph execution.
  
  This function returns any results that were computed before an error
  or timeout occurred during execution.
  
  ## Parameters
  
  - scheduler: The scheduler struct
  
  ## Returns
  
  A map of node IDs to their output values for completed nodes
  """
  @callback get_partial_results(scheduler :: struct()) :: outputs()
  
  @doc """
  Create a new scheduler of the specified type.
  
  ## Parameters
  
  - scheduler_type: The type of scheduler to create
  - opts: Additional options for the scheduler
  
  ## Returns
  
  A new scheduler struct
  
  ## Examples
  
      iex> scheduler = EmberEx.XCS.Schedulers.BaseScheduler.create("sequential")
      iex> scheduler = EmberEx.XCS.Schedulers.BaseScheduler.create("parallel", max_workers: 4)
  """
  @spec create(String.t(), keyword()) :: struct()
  def create(scheduler_type, opts \\ []) do
    case scheduler_type do
      "sequential" -> EmberEx.XCS.Schedulers.SequentialScheduler.new(opts)
      "parallel" -> EmberEx.XCS.Schedulers.ParallelScheduler.new(opts)
      "topological" -> EmberEx.XCS.Schedulers.TopologicalScheduler.new(opts)
      "wave" -> EmberEx.XCS.Schedulers.WaveScheduler.new(opts)
      "auto" -> 
        # Choose the best scheduler based on graph properties
        # For now, default to parallel
        EmberEx.XCS.Schedulers.ParallelScheduler.new(opts)
      _ -> 
        raise "Unknown scheduler type: #{scheduler_type}"
    end
  end
  
  @doc """
  Prepare the scheduler for execution with the given graph.
  
  This is a convenience function that delegates to the scheduler's prepare callback.
  
  ## Parameters
  
  - scheduler: The scheduler struct
  - graph: The XCS graph to prepare for execution
  
  ## Returns
  
  The prepared scheduler struct
  """
  @spec prepare(struct(), graph()) :: struct()
  def prepare(scheduler, graph) do
    module = scheduler.__struct__
    module.prepare(scheduler, graph)
  end
  
  @doc """
  Execute the graph with the given inputs.
  
  This is a convenience function that delegates to the scheduler's execute callback.
  
  ## Parameters
  
  - scheduler: The scheduler struct
  - graph: The XCS graph to execute
  - inputs: Input values for the graph's input nodes
  
  ## Returns
  
  A map of node IDs to their output values
  """
  @spec execute(struct(), graph(), inputs()) :: outputs()
  def execute(scheduler, graph, inputs) do
    module = scheduler.__struct__
    module.execute(scheduler, graph, inputs)
  end
  
  @doc """
  Get partial results from the graph execution.
  
  This is a convenience function that delegates to the scheduler's get_partial_results callback.
  
  ## Parameters
  
  - scheduler: The scheduler struct
  
  ## Returns
  
  A map of node IDs to their output values for completed nodes
  """
  @spec get_partial_results(struct()) :: outputs()
  def get_partial_results(scheduler) do
    module = scheduler.__struct__
    module.get_partial_results(scheduler)
  end
end
