defmodule EmberEx.Models.Usage do
  @moduledoc """
  Tracks usage metrics for language models.
  
  This module provides functionality for recording and analyzing model usage,
  including token counts, request counts, and associated costs.
  """
  
  @typedoc "Usage information for a model invocation"
  @type t :: %__MODULE__{
    prompt_tokens: non_neg_integer(),
    completion_tokens: non_neg_integer(),
    total_tokens: non_neg_integer(),
    model_id: String.t(),
    provider_id: atom(),
    timestamp: DateTime.t(),
    cost: float(),
    metadata: map()
  }
  
  defstruct [
    :prompt_tokens,
    :completion_tokens,
    :total_tokens,
    :model_id,
    :provider_id,
    :timestamp,
    :cost,
    :metadata
  ]
  
  @doc """
  Creates a new Usage struct.
  
  ## Parameters
  
  - params: Map or keyword list of parameters
  
  ## Returns
  
  A new Usage struct
  
  ## Examples
  
      iex> EmberEx.Models.Usage.new(
      ...>   prompt_tokens: 100,
      ...>   completion_tokens: 50,
      ...>   total_tokens: 150,
      ...>   model_id: "gpt-4",
      ...>   provider_id: :openai,
      ...>   cost: 0.03
      ...> )
  """
  @spec new(map() | keyword()) :: t()
  def new(params) do
    # Convert params to map if it's a keyword list
    params = if Keyword.keyword?(params), do: Map.new(params), else: params
    
    # Set defaults for missing fields
    params = Map.merge(%{
      prompt_tokens: 0,
      completion_tokens: 0,
      total_tokens: 0,
      timestamp: DateTime.utc_now(),
      cost: 0.0,
      metadata: %{}
    }, params)
    
    # Calculate total tokens if not provided
    params = if !Map.has_key?(params, :total_tokens) || params.total_tokens == 0 do
      Map.put(params, :total_tokens, params.prompt_tokens + params.completion_tokens)
    else
      params
    end
    
    struct(__MODULE__, params)
  end
  
  @doc """
  Records usage for a model request/response pair.
  
  ## Parameters
  
  - model_id: The ID of the model used
  - provider_id: The ID of the provider used
  - request: The request sent to the model
  - response: The response received from the model
  - provider_module: The provider module that handled the request
  
  ## Returns
  
  A new Usage struct with calculated metrics
  
  ## Examples
  
      iex> provider = EmberEx.Models.Providers.OpenAI
      iex> usage = EmberEx.Models.Usage.record(
      ...>   "gpt-4",
      ...>   :openai,
      ...>   %{messages: [%{role: "user", content: "Hello"}]},
      ...>   response,
      ...>   provider
      ...> )
  """
  @spec record(String.t(), atom(), map(), map(), module()) :: t()
  def record(model_id, provider_id, request, response, provider_module) do
    # Extract usage info from response using the provider
    usage_info = provider_module.extract_usage(model_id, response)
    
    # Calculate cost
    cost = provider_module.calculate_cost(model_id, request, response)
    
    # Create usage record
    usage_params = %{
      model_id: model_id,
      provider_id: provider_id,
      cost: cost,
      metadata: %{
        request_type: extract_request_type(request)
      }
    }
    
    # Add token counts if available
    usage_params = if usage_info do
      Map.merge(usage_params, usage_info)
    else
      usage_params
    end
    
    new(usage_params)
  end
  
  @doc """
  Merges multiple usage records.
  
  ## Parameters
  
  - usage_records: List of Usage structs to merge
  
  ## Returns
  
  A new Usage struct with aggregated metrics
  
  ## Examples
  
      iex> usages = [usage1, usage2, usage3]
      iex> EmberEx.Models.Usage.merge(usages)
  """
  @spec merge([t()]) :: t()
  def merge(usage_records) when is_list(usage_records) do
    # Initialize with zeros
    base = %{
      prompt_tokens: 0,
      completion_tokens: 0,
      total_tokens: 0,
      cost: 0.0,
      metadata: %{merged: true, count: length(usage_records)}
    }
    
    # Accumulate values from all records
    Enum.reduce(usage_records, base, fn usage, acc ->
      %{
        prompt_tokens: acc.prompt_tokens + usage.prompt_tokens,
        completion_tokens: acc.completion_tokens + usage.completion_tokens,
        total_tokens: acc.total_tokens + usage.total_tokens,
        cost: acc.cost + usage.cost,
        metadata: Map.merge(acc.metadata, %{
          models: Map.get(acc.metadata, :models, []) ++ [usage.model_id],
          providers: Map.get(acc.metadata, :providers, []) ++ [usage.provider_id]
        })
      }
    end)
    |> new()
  end
  
  # Private helpers
  
  defp extract_request_type(request) do
    cond do
      is_map(request) && Map.has_key?(request, :messages) -> :chat
      is_map(request) && Map.has_key?(request, :prompt) -> :completion
      is_binary(request) -> :simple
      true -> :unknown
    end
  end
end
