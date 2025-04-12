defmodule EmberEx.Config do
  @moduledoc """
  Configuration management for EmberEx.
  
  Provides a centralized system for managing configuration settings
  for models, operators, and other components of the framework.
  """
  
  @default_config %{
    models: %{
      default_provider: :openai,
      default_model: "gpt-3.5-turbo",
      providers: %{
        openai: %{
          api_key: nil,
          organization_id: nil
        },
        anthropic: %{
          api_key: nil
        }
      }
    },
    operators: %{
      retry: %{
        default_max_attempts: 3,
        default_backoff_type: :exponential
      },
      ensemble: %{
        default_timeout_ms: 30_000
      }
    },
    logging: %{
      level: :info,
      usage_tracking: true
    }
  }
  
  @doc """
  Get the current configuration.
  
  Returns the entire configuration map with default values merged with
  application environment settings.
  
  ## Returns
  
  A map containing the complete configuration
  """
  @spec get() :: map()
  def get do
    app_config = Application.get_env(:ember_ex, :config, %{})
    deep_merge(@default_config, app_config)
  end
  
  @doc """
  Get a specific configuration value by path.
  
  Retrieves a nested configuration value using a list of keys
  as the path to navigate the configuration map.
  
  ## Parameters
  
  - path: A list of keys representing the path to the desired value
  
  ## Returns
  
  The value at the specified path or nil if not found
  
  ## Examples
  
      iex> EmberEx.Config.get_in([:models, :default_provider])
      :openai
      
      iex> EmberEx.Config.get_in([:models, :providers, :openai, :api_key])
      nil
  """
  @spec get_in(list(atom() | String.t())) :: any()
  def get_in(path) when is_list(path) do
    get()
    |> Kernel.get_in(path)
  end
  
  @doc """
  Update a specific configuration value.
  
  Sets a value at the specified path in the configuration map and
  persists it to the application environment.
  
  ## Parameters
  
  - path: A list of keys representing the path to update
  - value: The new value to set
  
  ## Returns
  
  `:ok` if successful
  
  ## Examples
  
      iex> EmberEx.Config.put_in([:models, :default_provider], :anthropic)
      :ok
      
      iex> EmberEx.Config.put_in([:operators, :retry, :default_max_attempts], 5)
      :ok
  """
  @spec put_in(list(atom() | String.t()), any()) :: :ok
  def put_in(path, value) when is_list(path) do
    config = get()
    updated_config = put_in_path(config, path, value)
    Application.put_env(:ember_ex, :config, updated_config)
    :ok
  end
  
  @doc """
  Load configuration from environment variables.
  
  Looks for environment variables with the prefix `EMBER_EX_` and updates
  the configuration accordingly. Environment variable names are converted
  to configuration paths by replacing underscores with dots and converting
  to lowercase.
  
  ## Examples
  
  Given the environment variable `EMBER_EX_MODELS_PROVIDERS_OPENAI_API_KEY=sk-123`,
  this would set the configuration value at `[:models, :providers, :openai, :api_key]`
  to `"sk-123"`.
  
  ## Returns
  
  `:ok` if successful
  """
  @spec load_from_env() :: :ok
  def load_from_env do
    System.get_env()
    |> Enum.filter(fn {key, _} -> String.starts_with?(key, "EMBER_EX_") end)
    |> Enum.each(fn {key, value} ->
      # Remove prefix, convert to lowercase, and split by underscore
      path = key
        |> String.replace_prefix("EMBER_EX_", "")
        |> String.downcase()
        |> String.split("_")
        |> Enum.map(&String.to_atom/1)
      
      # Skip empty paths
      if path != [] do
        # Get current value if it exists
        current_value = try do
          get()
          |> get_in_safe(path)
        rescue
          _ -> nil
        end
        
        # Convert value based on destination type
        typed_value = case current_value do
          true when value in ["false", "0"] -> false
          false when value in ["true", "1"] -> true
          v when is_integer(v) -> String.to_integer(value)
          v when is_float(v) -> String.to_float(value)
          v when is_atom(v) and not is_boolean(v) -> String.to_atom(value)
          _ -> value
        end
        
        # Use our custom put_in_path function that safely handles paths
        config = get()
        updated_config = put_in_path(config, path, typed_value)
        Application.put_env(:ember_ex, :config, updated_config)
      end
    end)
    
    :ok
  end
  
  # Safe version of get_in that returns nil for invalid paths
  defp get_in_safe(_map, []), do: nil
  defp get_in_safe(map, [key | rest]) do
    if is_map(map) && Map.has_key?(map, key) do
      get_in_safe(map[key], rest)
    else
      nil
    end
  end
  
  # Private functions
  
  # Deep merge two maps
  defp deep_merge(a, b) when is_map(a) and is_map(b) do
    Map.merge(a, b, fn
      _, %{} = v1, %{} = v2 -> deep_merge(v1, v2)
      _, _, v2 -> v2
    end)
  end
  
  # Put a value at a nested path
  defp put_in_path(map, [key], value) do
    Map.put(map, key, value)
  end
  
  defp put_in_path(map, [key | rest], value) do
    current = Map.get(map, key, %{})
    Map.put(map, key, put_in_path(current, rest, value))
  end
end
