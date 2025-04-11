defmodule EmberEx.Models.UsageService do
  @moduledoc """
  Service for tracking and analyzing model usage.
  
  Provides methods for recording usage events, querying usage history,
  and calculating usage statistics and costs.
  """
  
  use GenServer
  require Logger
  
  alias EmberEx.Models.Usage
  
  @typedoc "UsageService state"
  @type state :: %{
    usage_records: [Usage.t()],
    max_records: pos_integer(),
    enabled: boolean()
  }
  
  # Server implementation
  
  @doc """
  Starts the UsageService GenServer.
  
  ## Parameters
  
  - opts: Options for the GenServer
    - name: The name to register the server under (default: __MODULE__)
    - max_records: Maximum number of usage records to keep (default: 1000)
    - enabled: Whether usage tracking is enabled (default: true)
  
  ## Returns
  
  GenServer start_link result
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
  end
  
  @impl true
  def init(opts) do
    state = %{
      usage_records: [],
      max_records: Keyword.get(opts, :max_records, 1000),
      enabled: Keyword.get(opts, :enabled, true)
    }
    
    Logger.info("Started UsageService (enabled: #{state.enabled}, max_records: #{state.max_records})")
    
    {:ok, state}
  end
  
  # Client API
  
  @doc """
  Record a new usage event.
  
  ## Parameters
  
  - usage: The Usage struct to record
  
  ## Returns
  
  `:ok`
  """
  @spec record_usage(Usage.t()) :: :ok
  def record_usage(usage) do
    GenServer.cast(__MODULE__, {:record_usage, usage})
  end
  
  @doc """
  Record usage for a model request/response pair.
  
  ## Parameters
  
  - model_id: The ID of the model used
  - provider_id: The ID of the provider used
  - request: The request sent to the model
  - response: The response received from the model
  
  ## Returns
  
  `:ok`
  """
  @spec record_model_usage(String.t(), atom(), map(), map()) :: :ok
  def record_model_usage(model_id, provider_id, request, response) do
    # Find the provider module
    provider_module = EmberEx.Registry.find_provider(provider_id)
    
    if provider_module do
      # Create usage record
      usage = Usage.record(model_id, provider_id, request, response, provider_module)
      
      # Record it
      record_usage(usage)
    else
      Logger.warning("Cannot record usage: provider #{provider_id} not found")
      :ok
    end
  end
  
  @doc """
  Enable or disable usage tracking.
  
  ## Parameters
  
  - enabled: Whether to enable usage tracking
  
  ## Returns
  
  `:ok`
  """
  @spec set_enabled(boolean()) :: :ok
  def set_enabled(enabled) do
    GenServer.cast(__MODULE__, {:set_enabled, enabled})
  end
  
  @doc """
  Get usage summary for a specific time period.
  
  ## Parameters
  
  - start_date: Start date for the summary (optional)
  - end_date: End date for the summary (optional)
  
  ## Returns
  
  A map with usage statistics
  """
  @spec get_usage_summary(DateTime.t() | nil, DateTime.t() | nil) :: map()
  def get_usage_summary(start_date \\ nil, end_date \\ nil) do
    GenServer.call(__MODULE__, {:get_usage_summary, start_date, end_date})
  end
  
  @doc """
  Get all usage records.
  
  ## Returns
  
  List of Usage structs
  """
  @spec get_all_records() :: [Usage.t()]
  def get_all_records do
    GenServer.call(__MODULE__, :get_all_records)
  end
  
  @doc """
  Clear all usage records.
  
  ## Returns
  
  `:ok`
  """
  @spec clear_records() :: :ok
  def clear_records do
    GenServer.cast(__MODULE__, :clear_records)
  end
  
  # Server callbacks
  
  @impl true
  def handle_cast({:record_usage, _usage}, %{enabled: false} = state) do
    # If disabled, don't record usage
    {:noreply, state}
  end
  
  @impl true
  def handle_cast({:record_usage, usage}, state) do
    # Add the new usage record to the list
    updated_records = [usage | state.usage_records]
    
    # Trim if we exceed the maximum number of records
    updated_records = if length(updated_records) > state.max_records do
      Enum.take(updated_records, state.max_records)
    else
      updated_records
    end
    
    {:noreply, %{state | usage_records: updated_records}}
  end
  
  @impl true
  def handle_cast({:set_enabled, enabled}, state) do
    Logger.info("UsageService tracking #{if enabled, do: "enabled", else: "disabled"}")
    {:noreply, %{state | enabled: enabled}}
  end
  
  @impl true
  def handle_cast(:clear_records, state) do
    Logger.info("Cleared all usage records")
    {:noreply, %{state | usage_records: []}}
  end
  
  @impl true
  def handle_call({:get_usage_summary, start_date, end_date}, _from, state) do
    # Filter records by date range
    filtered_records = filter_by_date_range(state.usage_records, start_date, end_date)
    
    # Calculate summary statistics
    summary = %{
      total_records: length(filtered_records),
      total_tokens: sum_by_field(filtered_records, :total_tokens),
      prompt_tokens: sum_by_field(filtered_records, :prompt_tokens),
      completion_tokens: sum_by_field(filtered_records, :completion_tokens),
      total_cost: sum_by_field(filtered_records, :cost),
      by_model: group_by_field(filtered_records, :model_id),
      by_provider: group_by_field(filtered_records, :provider_id),
      time_range: %{
        start: start_date || (List.last(filtered_records) || %{timestamp: nil}).timestamp,
        end: end_date || (List.first(filtered_records) || %{timestamp: nil}).timestamp
      }
    }
    
    {:reply, summary, state}
  end
  
  @impl true
  def handle_call(:get_all_records, _from, state) do
    {:reply, state.usage_records, state}
  end
  
  # Private helpers
  
  defp filter_by_date_range(records, nil, nil), do: records
  
  defp filter_by_date_range(records, start_date, nil) do
    Enum.filter(records, fn record -> 
      DateTime.compare(record.timestamp, start_date) in [:gt, :eq]
    end)
  end
  
  defp filter_by_date_range(records, nil, end_date) do
    Enum.filter(records, fn record -> 
      DateTime.compare(record.timestamp, end_date) in [:lt, :eq]
    end)
  end
  
  defp filter_by_date_range(records, start_date, end_date) do
    Enum.filter(records, fn record -> 
      DateTime.compare(record.timestamp, start_date) in [:gt, :eq] &&
      DateTime.compare(record.timestamp, end_date) in [:lt, :eq]
    end)
  end
  
  defp sum_by_field(records, field) do
    Enum.reduce(records, 0, fn record, acc -> 
      acc + Map.get(record, field, 0)
    end)
  end
  
  defp group_by_field(records, field) do
    records
    |> Enum.group_by(fn record -> Map.get(record, field) end)
    |> Enum.map(fn {key, grouped_records} -> 
      usage = Usage.merge(grouped_records)
      {key, %{
        count: length(grouped_records),
        total_tokens: usage.total_tokens,
        prompt_tokens: usage.prompt_tokens,
        completion_tokens: usage.completion_tokens,
        cost: usage.cost
      }}
    end)
    |> Map.new()
  end
end
