defmodule EmberEx.Context.ExecutionContext do
  @moduledoc """
  Execution context for EmberEx operations.
  
  This module provides a way to maintain context during the execution of operators,
  including configuration, metadata, and state that should be passed along the
  execution pipeline.
  """
  
  @typedoc "Execution context struct type"
  @type t :: %__MODULE__{
    id: String.t(),
    config: map(),
    metadata: map(),
    state: map(),
    parent_id: String.t() | nil,
    created_at: DateTime.t()
  }
  
  defstruct [
    :id,
    :config,
    :metadata,
    :state,
    :parent_id,
    :created_at
  ]
  
  @doc """
  Create a new execution context.
  
  ## Parameters
  
  - config: Configuration for the execution context
  - metadata: Metadata for the execution context
  - parent_id: ID of the parent context, if any
  
  ## Returns
  
  A new execution context struct
  
  ## Examples
  
      iex> EmberEx.Context.ExecutionContext.new(%{model: "openai/gpt-4"}, %{user_id: "123"})
      %EmberEx.Context.ExecutionContext{
        id: "ctx_abcdefg",
        config: %{model: "openai/gpt-4"},
        metadata: %{user_id: "123"},
        state: %{},
        parent_id: nil,
        created_at: ~U[2023-01-01 00:00:00Z]
      }
  """
  @spec new(map(), map(), String.t() | nil) :: t()
  def new(config \\ %{}, metadata \\ %{}, parent_id \\ nil) do
    %__MODULE__{
      id: generate_id(),
      config: config,
      metadata: metadata,
      state: %{},
      parent_id: parent_id,
      created_at: DateTime.utc_now()
    }
  end
  
  @doc """
  Create a child context from a parent context.
  
  ## Parameters
  
  - parent: The parent context
  - config_override: Configuration overrides for the child context
  - metadata_override: Metadata overrides for the child context
  
  ## Returns
  
  A new child execution context struct
  
  ## Examples
  
      iex> parent = EmberEx.Context.ExecutionContext.new(%{model: "openai/gpt-4"}, %{user_id: "123"})
      iex> EmberEx.Context.ExecutionContext.create_child(parent, %{temperature: 0.7})
      %EmberEx.Context.ExecutionContext{
        id: "ctx_hijklmn",
        config: %{model: "openai/gpt-4", temperature: 0.7},
        metadata: %{user_id: "123"},
        state: %{},
        parent_id: "ctx_abcdefg",
        created_at: ~U[2023-01-01 00:00:00Z]
      }
  """
  @spec create_child(t(), map(), map()) :: t()
  def create_child(parent, config_override \\ %{}, metadata_override \\ %{}) do
    # Merge parent config with override
    config = Map.merge(parent.config, config_override)
    
    # Merge parent metadata with override
    metadata = Map.merge(parent.metadata, metadata_override)
    
    # Create a new context with the parent's ID
    new(config, metadata, parent.id)
  end
  
  @doc """
  Update the state of an execution context.
  
  ## Parameters
  
  - context: The execution context to update
  - key: The state key to update
  - value: The new value for the state key
  
  ## Returns
  
  The updated execution context struct
  
  ## Examples
  
      iex> context = EmberEx.Context.ExecutionContext.new()
      iex> EmberEx.Context.ExecutionContext.update_state(context, :status, :running)
      %EmberEx.Context.ExecutionContext{
        state: %{status: :running},
        ...
      }
  """
  @spec update_state(t(), atom() | String.t(), any()) :: t()
  def update_state(context, key, value) do
    new_state = Map.put(context.state, key, value)
    %{context | state: new_state}
  end
  
  @doc """
  Update multiple state values of an execution context.
  
  ## Parameters
  
  - context: The execution context to update
  - updates: A map of state updates
  
  ## Returns
  
  The updated execution context struct
  
  ## Examples
  
      iex> context = EmberEx.Context.ExecutionContext.new()
      iex> EmberEx.Context.ExecutionContext.update_state_map(context, %{status: :running, step: 1})
      %EmberEx.Context.ExecutionContext{
        state: %{status: :running, step: 1},
        ...
      }
  """
  @spec update_state_map(t(), map()) :: t()
  def update_state_map(context, updates) do
    new_state = Map.merge(context.state, updates)
    %{context | state: new_state}
  end
  
  @doc """
  Get a configuration value from the context.
  
  ## Parameters
  
  - context: The execution context
  - key: The configuration key to get
  - default: The default value to return if the key is not found
  
  ## Returns
  
  The configuration value, or the default value if the key is not found
  
  ## Examples
  
      iex> context = EmberEx.Context.ExecutionContext.new(%{model: "openai/gpt-4"})
      iex> EmberEx.Context.ExecutionContext.get_config(context, :model)
      "openai/gpt-4"
      
      iex> EmberEx.Context.ExecutionContext.get_config(context, :temperature, 0.7)
      0.7
  """
  @spec get_config(t(), atom() | String.t(), any()) :: any()
  def get_config(context, key, default \\ nil) do
    Map.get(context.config, key, default)
  end
  
  @doc """
  Update the configuration of an execution context.
  
  ## Parameters
  
  - context: The execution context to update
  - key: The configuration key to update
  - value: The new value for the configuration key
  
  ## Returns
  
  The updated execution context struct
  
  ## Examples
  
      iex> context = EmberEx.Context.ExecutionContext.new()
      iex> EmberEx.Context.ExecutionContext.update_config(context, :model, "openai/gpt-4")
      %EmberEx.Context.ExecutionContext{
        config: %{model: "openai/gpt-4"},
        ...
      }
  """
  @spec update_config(t(), atom() | String.t(), any()) :: t()
  def update_config(context, key, value) do
    new_config = Map.put(context.config, key, value)
    %{context | config: new_config}
  end
  
  @doc """
  Update multiple configuration values of an execution context.
  
  ## Parameters
  
  - context: The execution context to update
  - updates: A map of configuration updates
  
  ## Returns
  
  The updated execution context struct
  
  ## Examples
  
      iex> context = EmberEx.Context.ExecutionContext.new()
      iex> EmberEx.Context.ExecutionContext.update_config_map(context, %{model: "openai/gpt-4", temperature: 0.7})
      %EmberEx.Context.ExecutionContext{
        config: %{model: "openai/gpt-4", temperature: 0.7},
        ...
      }
  """
  @spec update_config_map(t(), map()) :: t()
  def update_config_map(context, updates) do
    new_config = Map.merge(context.config, updates)
    %{context | config: new_config}
  end
  
  # Private functions
  
  defp generate_id do
    "ctx_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end
end
