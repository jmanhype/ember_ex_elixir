defmodule EmberEx.Config.Manager do
  @moduledoc """
  Configuration management system for EmberEx.
  
  This module provides a centralized way to manage configuration settings for the EmberEx framework.
  It supports both global and context-specific configuration, with the ability to override
  global settings in specific contexts.
  
  Configuration is hierarchical and can be accessed using dot-notation paths.
  """
  
  @typedoc "Configuration value type"
  @type config_value :: any()
  
  @typedoc "Configuration path type"
  @type config_path :: String.t() | atom() | list(String.t() | atom())
  
  @typedoc "Configuration context type"
  @type config_context :: atom() | String.t()
  
  @table_name :ember_ex_config
  
  @doc """
  Initialize the configuration manager.
  
  ## Returns
  
  `:ok`
  """
  @spec init() :: :ok
  def init do
    # Create the ETS table if it doesn't exist
    if :ets.info(@table_name) == :undefined do
      :ets.new(@table_name, [:named_table, :set, :public])
      
      # Initialize with default configuration
      set_defaults()
    end
    :ok
  end
  
  @doc """
  Get a configuration value.
  
  ## Parameters
  
  - path: The path to the configuration value
  - context: The configuration context (optional)
  - default: The default value to return if the configuration value is not found
  
  ## Returns
  
  The configuration value, or the default value if the configuration value is not found.
  
  ## Examples
  
      iex> EmberEx.Config.Manager.get("models.default")
      "openai/gpt-4"
      
      iex> EmberEx.Config.Manager.get("models.default", :test, "test-model")
      "test-model"
  """
  @spec get(config_path(), config_context() | nil, config_value()) :: config_value()
  def get(path, context \\ nil, default \\ nil) do
    # Normalize the path
    path = normalize_path(path)
    
    # Try to get the configuration value from the context-specific configuration first
    case context do
      nil ->
        # Get the value from the global configuration
        get_from_global(path, default)
        
      context ->
        # Get the value from the context-specific configuration, falling back to the global configuration
        get_from_context(path, context, default)
    end
  end
  
  @doc """
  Set a configuration value.
  
  ## Parameters
  
  - path: The path to the configuration value
  - value: The value to set
  - context: The configuration context (optional)
  
  ## Returns
  
  `:ok`
  
  ## Examples
  
      iex> EmberEx.Config.Manager.set("models.default", "openai/gpt-4")
      :ok
      
      iex> EmberEx.Config.Manager.set("models.default", "test-model", :test)
      :ok
  """
  @spec set(config_path(), config_value(), config_context() | nil) :: :ok
  def set(path, value, context \\ nil) do
    # Normalize the path
    path = normalize_path(path)
    
    # Set the configuration value
    case context do
      nil ->
        # Set the value in the global configuration
        set_in_global(path, value)
        
      context ->
        # Set the value in the context-specific configuration
        set_in_context(path, value, context)
    end
  end
  
  @doc """
  Check if a configuration value exists.
  
  ## Parameters
  
  - path: The path to the configuration value
  - context: The configuration context (optional)
  
  ## Returns
  
  `true` if the configuration value exists, otherwise `false`
  
  ## Examples
  
      iex> EmberEx.Config.Manager.exists?("models.default")
      true
      
      iex> EmberEx.Config.Manager.exists?("nonexistent.path")
      false
  """
  @spec exists?(config_path(), config_context() | nil) :: boolean()
  def exists?(path, context \\ nil) do
    # Normalize the path
    path = normalize_path(path)
    
    # Check if the configuration value exists
    case context do
      nil ->
        # Check in the global configuration
        exists_in_global?(path)
        
      context ->
        # Check in the context-specific configuration, falling back to the global configuration
        exists_in_context?(path, context)
    end
  end
  
  @doc """
  Remove a configuration value.
  
  ## Parameters
  
  - path: The path to the configuration value
  - context: The configuration context (optional)
  
  ## Returns
  
  `:ok`
  
  ## Examples
  
      iex> EmberEx.Config.Manager.remove("models.default")
      :ok
      
      iex> EmberEx.Config.Manager.remove("models.default", :test)
      :ok
  """
  @spec remove(config_path(), config_context() | nil) :: :ok
  def remove(path, context \\ nil) do
    # Normalize the path
    path = normalize_path(path)
    
    # Remove the configuration value
    case context do
      nil ->
        # Remove from the global configuration
        remove_from_global(path)
        
      context ->
        # Remove from the context-specific configuration
        remove_from_context(path, context)
    end
  end
  
  @doc """
  Get all configuration values.
  
  ## Parameters
  
  - context: The configuration context (optional)
  
  ## Returns
  
  A map of all configuration values
  
  ## Examples
  
      iex> EmberEx.Config.Manager.get_all()
      %{"models" => %{"default" => "openai/gpt-4"}}
      
      iex> EmberEx.Config.Manager.get_all(:test)
      %{"models" => %{"default" => "test-model"}}
  """
  @spec get_all(config_context() | nil) :: map()
  def get_all(context \\ nil) do
    # Get all configuration values
    case context do
      nil ->
        # Get all global configuration values
        get_all_global()
        
      context ->
        # Get all context-specific configuration values, merged with global values
        get_all_context(context)
    end
  end
  
  # Private functions
  
  defp set_defaults do
    # Set default configuration values
    defaults = %{
      "models" => %{
        "default" => "openai/gpt-4",
        "providers" => %{
          "openai" => %{
            "api_key_env" => "OPENAI_API_KEY",
            "api_base_env" => "OPENAI_API_BASE"
          }
        }
      },
      "xcs" => %{
        "parallel" => true,
        "max_parallelism" => 10
      },
      "logging" => %{
        "level" => "info"
      }
    }
    
    # Set each default value
    for {key, value} <- flatten_map(defaults) do
      set(key, value)
    end
  end
  
  defp flatten_map(map, prefix \\ "") do
    Enum.flat_map(map, fn {key, value} ->
      key_str = to_string(key)
      path = if prefix == "", do: key_str, else: "#{prefix}.#{key_str}"
      
      if is_map(value) do
        flatten_map(value, path)
      else
        [{path, value}]
      end
    end)
  end
  
  defp normalize_path(path) when is_atom(path), do: to_string(path)
  defp normalize_path(path) when is_binary(path), do: path
  defp normalize_path(path) when is_list(path) do
    path
    |> Enum.map(fn
      p when is_atom(p) -> to_string(p)
      p -> p
    end)
    |> Enum.join(".")
  end
  
  defp get_from_global(path, default) do
    case :ets.lookup(@table_name, path) do
      [] -> default
      [{^path, value}] -> value
    end
  end
  
  defp get_from_context(path, context, default) do
    context_path = "#{context}.#{path}"
    
    case :ets.lookup(@table_name, context_path) do
      [] -> get_from_global(path, default)
      [{^context_path, value}] -> value
    end
  end
  
  defp set_in_global(path, value) do
    :ets.insert(@table_name, {path, value})
    :ok
  end
  
  defp set_in_context(path, value, context) do
    context_path = "#{context}.#{path}"
    :ets.insert(@table_name, {context_path, value})
    :ok
  end
  
  defp exists_in_global?(path) do
    case :ets.lookup(@table_name, path) do
      [] -> false
      _ -> true
    end
  end
  
  defp exists_in_context?(path, context) do
    context_path = "#{context}.#{path}"
    
    case :ets.lookup(@table_name, context_path) do
      [] -> exists_in_global?(path)
      _ -> true
    end
  end
  
  defp remove_from_global(path) do
    :ets.delete(@table_name, path)
    :ok
  end
  
  defp remove_from_context(path, context) do
    context_path = "#{context}.#{path}"
    :ets.delete(@table_name, context_path)
    :ok
  end
  
  defp get_all_global do
    # Get all keys from the ETS table that don't have a context prefix
    @table_name
    |> :ets.tab2list()
    |> Enum.filter(fn {key, _} -> not String.contains?(key, ".") end)
    |> Enum.map(fn {key, value} -> {key, value} end)
    |> Enum.into(%{})
  end
  
  defp get_all_context(context) do
    # Get all keys from the ETS table with the given context prefix
    context_configs = @table_name
    |> :ets.tab2list()
    |> Enum.filter(fn {key, _} -> String.starts_with?(key, "#{context}.") end)
    |> Enum.map(fn {key, value} -> {String.replace_prefix(key, "#{context}.", ""), value} end)
    |> Enum.into(%{})
    
    # Merge with global configuration
    Map.merge(get_all_global(), context_configs)
  end
end
