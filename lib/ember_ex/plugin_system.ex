defmodule EmberEx.PluginSystem do
  @moduledoc """
  Plugin system for EmberEx.
  
  This module provides functionality for loading, registering, and managing plugins.
  Plugins can extend the functionality of the EmberEx framework by adding new:
  - Operators
  - Specifications
  - Models
  - Utilities
  
  ## Plugin Structure
  
  A plugin module must implement the `EmberEx.PluginSystem.Plugin` behaviour.
  """
  
  alias EmberEx.PluginSystem.Registry
  
  @doc """
  Initialize the plugin system.
  """
  @spec init() :: :ok
  def init do
    # Create an empty plugin registry ETS table
    Registry.init()
    :ok
  end
  
  @doc """
  Register a plugin with the plugin system.
  
  ## Parameters
  
  - plugin_module: The module implementing the plugin
  
  ## Returns
  
  `:ok` if the plugin was registered successfully, otherwise `{:error, reason}`
  """
  @spec register(module()) :: :ok | {:error, term()}
  def register(plugin_module) do
    with {:ok, plugin_info} <- validate_plugin(plugin_module),
         :ok <- Registry.add_plugin(plugin_info) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end
  
  @doc """
  Unregister a plugin from the plugin system.
  
  ## Parameters
  
  - plugin_name: The name of the plugin to unregister
  
  ## Returns
  
  `:ok` if the plugin was unregistered successfully, otherwise `{:error, reason}`
  """
  @spec unregister(String.t()) :: :ok | {:error, term()}
  def unregister(plugin_name) do
    Registry.remove_plugin(plugin_name)
  end
  
  @doc """
  Get a list of all registered plugins.
  
  ## Returns
  
  A list of plugin information maps
  """
  @spec list_plugins() :: [map()]
  def list_plugins do
    Registry.list_plugins()
  end
  
  @doc """
  Validate a plugin module to ensure it implements the required behavior.
  
  ## Parameters
  
  - plugin_module: The module implementing the plugin
  
  ## Returns
  
  `{:ok, plugin_info}` if the plugin is valid, otherwise `{:error, reason}`
  """
  @spec validate_plugin(module()) :: {:ok, map()} | {:error, term()}
  defp validate_plugin(plugin_module) do
    # Check if the module exists and implements the required plugin behavior
    if Code.ensure_loaded?(plugin_module) and function_exported?(plugin_module, :info, 0) do
      case plugin_module.info() do
        %{name: name, version: version} when is_binary(name) and is_binary(version) ->
          {:ok, %{
            name: name,
            version: version,
            module: plugin_module
          }}
        _ ->
          {:error, "Plugin info must return a map with :name and :version keys"}
      end
    else
      {:error, "Plugin module must implement the info/0 function"}
    end
  end
end

defmodule EmberEx.PluginSystem.Plugin do
  @moduledoc """
  Behaviour for EmberEx plugins.
  
  Any module implementing a plugin for EmberEx must implement this behaviour.
  """
  
  @doc """
  Returns information about the plugin.
  
  ## Returns
  
  A map containing at least the following keys:
  - `:name` - The name of the plugin (string)
  - `:version` - The version of the plugin (string)
  """
  @callback info() :: %{required(:name) => String.t(), required(:version) => String.t(), optional(atom()) => any()}
  
  @doc """
  Initialize the plugin.
  
  Called when the plugin is registered with the system.
  
  ## Returns
  
  `:ok` if initialization was successful, otherwise `{:error, reason}`
  """
  @callback init() :: :ok | {:error, term()}
  
  @optional_callbacks [init: 0]
end

defmodule EmberEx.PluginSystem.Registry do
  @moduledoc """
  Registry for managing plugins in the EmberEx plugin system.
  
  This module provides functions for registering, unregistering, and querying plugins.
  """
  
  @table_name :ember_ex_plugins
  
  @doc """
  Initialize the plugin registry.
  """
  @spec init() :: :ok
  def init do
    # Create the ETS table if it doesn't exist
    if :ets.info(@table_name) == :undefined do
      :ets.new(@table_name, [:named_table, :set, :public])
    end
    :ok
  end
  
  @doc """
  Add a plugin to the registry.
  
  ## Parameters
  
  - plugin_info: Information about the plugin
  
  ## Returns
  
  `:ok` if the plugin was added successfully
  """
  @spec add_plugin(map()) :: :ok
  def add_plugin(plugin_info) do
    :ets.insert(@table_name, {plugin_info.name, plugin_info})
    # Initialize the plugin if it has an init function
    if function_exported?(plugin_info.module, :init, 0) do
      _ = plugin_info.module.init()
    end
    :ok
  end
  
  @doc """
  Remove a plugin from the registry.
  
  ## Parameters
  
  - plugin_name: The name of the plugin to remove
  
  ## Returns
  
  `:ok` if the plugin was removed successfully, otherwise `{:error, reason}`
  """
  @spec remove_plugin(String.t()) :: :ok | {:error, term()}
  def remove_plugin(plugin_name) do
    case :ets.lookup(@table_name, plugin_name) do
      [] -> {:error, "Plugin not found"}
      [{^plugin_name, _}] ->
        :ets.delete(@table_name, plugin_name)
        :ok
    end
  end
  
  @doc """
  Get a list of all registered plugins.
  
  ## Returns
  
  A list of plugin information maps
  """
  @spec list_plugins() :: [map()]
  def list_plugins do
    @table_name
    |> :ets.tab2list()
    |> Enum.map(fn {_, plugin_info} -> plugin_info end)
  end
  
  @doc """
  Get a plugin by name.
  
  ## Parameters
  
  - plugin_name: The name of the plugin to get
  
  ## Returns
  
  The plugin information map if found, otherwise `nil`
  """
  @spec get_plugin(String.t()) :: map() | nil
  def get_plugin(plugin_name) do
    case :ets.lookup(@table_name, plugin_name) do
      [] -> nil
      [{^plugin_name, plugin_info}] -> plugin_info
    end
  end
end
