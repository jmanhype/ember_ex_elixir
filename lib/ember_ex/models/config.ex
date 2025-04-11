defmodule EmberEx.Models.Config do
  @moduledoc """
  Global configuration for model behavior.
  
  This module provides a way to manage configuration for language models,
  including global defaults and context-specific overrides.
  """
  
  use Agent
  
  @typedoc "Configuration map type"
  @type config :: %{
    temperature: float(),
    max_tokens: integer() | nil,
    timeout: integer() | nil,
    top_p: float(),
    top_k: integer() | nil,
    stop_sequences: list(String.t()) | nil,
    thread_local_overrides: map()
  }
  
  @doc """
  Start the configuration agent.
  
  This function is called by the application supervisor.
  
  ## Parameters
  
  - _: Ignored
  
  ## Returns
  
  `{:ok, pid}` if successful, `{:error, reason}` otherwise
  """
  @spec start_link(any()) :: {:ok, pid()} | {:error, term()}
  def start_link(_) do
    Agent.start_link(fn -> 
      %{
        temperature: 0.7,
        max_tokens: nil,
        timeout: nil,
        top_p: 1.0,
        top_k: nil,
        stop_sequences: nil,
        thread_local_overrides: %{}
      }
    end, name: __MODULE__)
  end
  
  @doc """
  Update the configuration.
  
  ## Parameters
  
  - config: A map of configuration values to update
  
  ## Returns
  
  `:ok`
  
  ## Examples
  
      iex> EmberEx.Models.Config.update(%{temperature: 0.5})
      :ok
  """
  @spec update(map()) :: :ok
  def update(config) do
    Agent.update(__MODULE__, &Map.merge(&1, config))
  end
  
  @doc """
  Get the effective configuration.
  
  ## Returns
  
  The current configuration map
  
  ## Examples
  
      iex> EmberEx.Models.Config.get_effective_config()
      %{temperature: 0.7, max_tokens: nil, ...}
  """
  @spec get_effective_config() :: config()
  def get_effective_config do
    Agent.get(__MODULE__, & &1)
  end
end

defmodule EmberEx.Models.Configure do
  @moduledoc """
  Context manager for temporary configuration.
  
  This module provides a way to temporarily override configuration
  for a specific block of code.
  """
  
  @doc """
  Configure the model system for a block of code.
  
  This macro provides a way to temporarily override configuration
  for a specific block of code. The original configuration is restored
  after the block is executed.
  
  ## Parameters
  
  - config: A map of configuration values to override
  - block: The block of code to execute with the overridden configuration
  
  ## Returns
  
  The result of the block
  
  ## Examples
  
      iex> EmberEx.Models.Configure.configure(%{temperature: 0.5}) do
      ...>   model = EmberEx.Models.model("gpt-4o")
      ...>   model.("What is the capital of France?")
      ...> end
  """
  defmacro configure(config, do: block) do
    quote do
      original_config = EmberEx.Models.Config.get_effective_config()
      try do
        EmberEx.Models.Config.update(unquote(config))
        unquote(block)
      after
        EmberEx.Models.Config.update(original_config)
      end
    end
  end
end
