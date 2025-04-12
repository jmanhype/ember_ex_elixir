defmodule EmberEx.Metrics.Storage do
  @moduledoc """
  Storage backend for metrics collection in EmberEx.
  
  This module provides an ETS-based storage implementation for metrics,
  enabling efficient in-memory storage and retrieval.
  """
  
  @table_name :ember_ex_metrics
  
  @doc """
  Initialize the metrics storage.
  """
  @spec init() :: :ok
  def init do
    # Create the ETS table if it doesn't exist
    if :ets.info(@table_name) == :undefined do
      :ets.new(@table_name, [:named_table, :bag, :public])
    end
    :ok
  end
  
  @doc """
  Store a metric in the metrics storage.
  
  ## Parameters
  
  - metric: The metric to store
  
  ## Returns
  
  `:ok`
  """
  @spec store(map()) :: :ok
  def store(metric) do
    :ets.insert(@table_name, {metric.name, metric})
    :ok
  end
  
  @doc """
  Get all metrics from the storage.
  
  ## Returns
  
  A list of metrics
  """
  @spec get_all() :: [map()]
  def get_all do
    @table_name
    |> :ets.tab2list()
    |> Enum.map(fn {_, metric} -> metric end)
  end
  
  @doc """
  Get metrics with the given name.
  
  ## Parameters
  
  - name: The name of the metrics to get
  
  ## Returns
  
  A list of metrics with the given name
  """
  @spec get_by_name(String.t()) :: [map()]
  def get_by_name(name) do
    @table_name
    |> :ets.lookup(name)
    |> Enum.map(fn {_, metric} -> metric end)
  end
  
  @doc """
  Clear all stored metrics.
  
  ## Returns
  
  `:ok`
  """
  @spec clear() :: :ok
  def clear do
    :ets.delete_all_objects(@table_name)
    :ok
  end
end
