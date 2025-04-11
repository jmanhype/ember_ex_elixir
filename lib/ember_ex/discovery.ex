defmodule EmberEx.Discovery do
  @moduledoc """
  Component discovery for EmberEx.
  
  Provides utilities for dynamically discovering and loading
  EmberEx components like operators and providers.
  """
  
  require Logger
  
  @doc """
  Discover and register all available providers.
  
  Scans all loaded modules that implement the Provider behavior
  and registers them with the Registry.
  
  ## Returns
  
  A list of the registered provider names
  """
  @spec discover_providers() :: [atom()]
  def discover_providers do
    providers = 
      :code.all_loaded()
      |> Enum.map(fn {module, _} -> module end)
      |> Enum.filter(&implements_behaviour?(&1, EmberEx.Models.Providers.Base))
      |> Enum.map(fn module -> 
        name = module_to_name(module, "EmberEx.Models.Providers")
        EmberEx.Registry.register_provider(name, module)
        name
      end)
    
    Logger.info("Discovered #{length(providers)} providers: #{inspect(providers)}")
    providers
  end
  
  @doc """
  Discover and register all available operators.
  
  Scans all loaded modules that use EmberEx.Operators.BaseOperator
  and registers them with the Registry.
  
  ## Returns
  
  A list of the registered operator names
  """
  @spec discover_operators() :: [atom()]
  def discover_operators do
    operators = 
      :code.all_loaded()
      |> Enum.map(fn {module, _} -> module end)
      |> Enum.filter(&uses_module?(&1, EmberEx.Operators.BaseOperator))
      |> Enum.map(fn module -> 
        name = module_to_name(module, "EmberEx.Operators")
        EmberEx.Registry.register_operator(name, module)
        name
      end)
    
    Logger.info("Discovered #{length(operators)} operators: #{inspect(operators)}")
    operators
  end
  
  @doc """
  Discover and register components from a specific OTP application.
  
  ## Parameters
  
  - app: The OTP application name to scan
  
  ## Returns
  
  A map with lists of discovered component names by type
  """
  @spec discover_from_app(atom()) :: %{
    operators: [atom()],
    providers: [atom()]
  }
  def discover_from_app(app) do
    # Get all modules from the application
    {:ok, modules} = :application.get_key(app, :modules)
    
    # Find and register providers
    providers = 
      modules
      |> Enum.filter(&implements_behaviour?(&1, EmberEx.Models.Providers.Base))
      |> Enum.map(fn module -> 
        name = module_to_name(module, "EmberEx.Models.Providers")
        EmberEx.Registry.register_provider(name, module)
        name
      end)
    
    # Find and register operators
    operators = 
      modules
      |> Enum.filter(&uses_module?(&1, EmberEx.Operators.BaseOperator))
      |> Enum.map(fn module -> 
        name = module_to_name(module, "EmberEx.Operators")
        EmberEx.Registry.register_operator(name, module)
        name
      end)
    
    Logger.info("Discovered from #{app}: #{length(providers)} providers, #{length(operators)} operators")
    
    %{
      operators: operators,
      providers: providers
    }
  end
  
  @doc """
  Initialize the component registry.
  
  Starts the registry GenServer and discovers all available components.
  
  ## Returns
  
  `:ok` if successful
  """
  @spec initialize() :: :ok
  def initialize do
    case EmberEx.Registry.start_link() do
      {:ok, _pid} ->
        discover_providers()
        discover_operators()
        :ok
        
      {:error, {:already_started, _pid}} ->
        discover_providers()
        discover_operators()
        :ok
        
      {:error, reason} ->
        Logger.error("Failed to start EmberEx.Registry: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  # Private helpers
  
  @doc false
  @spec implements_behaviour?(module(), module()) :: boolean()
  def implements_behaviour?(module, behaviour) do
    # Check if the module implements the given behaviour
    try do
      behaviours = module.module_info(:attributes)[:behaviour] || []
      behaviour in behaviours
    rescue
      _ -> false
    end
  end
  
  @doc false
  @spec uses_module?(module(), module()) :: boolean()
  def uses_module?(module, _base_module) do
    # Check if the module uses the given base module
    try do
      # Check if the module exports new/0, new/1, or new/2, which are common in operators
      exports = module.module_info(:exports)
      if Keyword.get(exports, :new) do
        # This is a heuristic - we could improve this by checking the module's source
        # or by requiring operators to implement a specific function
        String.starts_with?(to_string(module), "Elixir.EmberEx.Operators")
      else
        false
      end
    rescue
      _ -> false
    end
  end
  
  @doc false
  @spec module_to_name(module(), String.t()) :: atom()
  def module_to_name(module, prefix) do
    # Convert a module name like EmberEx.Models.Providers.OpenAI to :openai
    module_str = to_string(module)
    
    if String.starts_with?(module_str, "Elixir." <> prefix) do
      # Extract the last part of the module name
      module_str
      |> String.replace_prefix("Elixir." <> prefix <> ".", "")
      |> Macro.underscore()
      |> String.to_atom()
    else
      # If the module doesn't match the expected prefix, use a fallback approach
      module_str
      |> String.replace_prefix("Elixir.", "")
      |> String.split(".")
      |> List.last()
      |> Macro.underscore()
      |> String.to_atom()
    end
  end
end
