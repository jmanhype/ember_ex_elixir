defmodule EmberEx.Registry do
  @moduledoc """
  Registry for EmberEx components.
  
  Provides a central registry for discovering and accessing operators,
  model providers, models, and other extension components.
  
  The registry supports auto-discovery of components via module attributes
  and provides a comprehensive API for registering and finding components.
  """
  
  use GenServer
  require Logger
  
  @type component_type :: :operators | :providers | :specifications | :models
  @type registry :: %{
    operators: %{optional(atom()) => module()},
    providers: %{optional(atom()) => module()},
    specifications: %{optional(atom()) => struct()},
    models: %{optional(String.t()) => map()},
    discovery_paths: [String.t()]
  }
  
  @doc """
  Start the registry server.
  
  ## Parameters
  
  - opts: Options to pass to the GenServer
  
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
      operators: %{},
      providers: %{},
      specifications: %{},
      models: %{},
      discovery_paths: Keyword.get(opts, :discovery_paths, [])
    }
    
    # Run auto-discovery if enabled
    if Keyword.get(opts, :auto_discover, false) do
      send(self(), :perform_discovery)
    end
    
    {:ok, state}
  end
  
  # Client API
  
  @doc """
  Register an operator implementation.
  
  ## Parameters
  
  - name: The name to register the operator under
  - module: The module implementing the operator
  
  ## Returns
  
  `:ok` if successful
  """
  @spec register_operator(atom(), module()) :: :ok
  def register_operator(name, module) do
    GenServer.call(__MODULE__, {:register, :operators, name, module})
  end
  
  @doc """
  Register a provider implementation.
  
  ## Parameters
  
  - name: The name to register the provider under
  - module: The module implementing the provider
  
  ## Returns
  
  `:ok` if successful
  """
  @spec register_provider(atom(), module()) :: :ok
  def register_provider(name, module) do
    GenServer.call(__MODULE__, {:register, :providers, name, module})
  end
  
  @doc """
  Register a specification.
  
  ## Parameters
  
  - name: The name to register the specification under
  - spec: The specification struct
  
  ## Returns
  
  `:ok` if successful
  """
  @spec register_specification(atom(), struct()) :: :ok
  def register_specification(name, spec) do
    GenServer.call(__MODULE__, {:register, :specifications, name, spec})
  end
  
  @doc """
  Find an operator by name.
  
  ## Parameters
  
  - name: The name of the operator to find
  
  ## Returns
  
  The operator module or nil if not found
  """
  @spec find_operator(atom()) :: module() | nil
  def find_operator(name) do
    GenServer.call(__MODULE__, {:find, :operators, name})
  end
  
  @doc """
  Find a provider by name.
  
  ## Parameters
  
  - name: The name of the provider to find
  
  ## Returns
  
  The provider module or nil if not found
  """
  @spec find_provider(atom()) :: module() | nil
  def find_provider(name) do
    GenServer.call(__MODULE__, {:find, :providers, name})
  end
  
  @doc """
  Find a specification by name.
  
  ## Parameters
  
  - name: The name of the specification to find
  
  ## Returns
  
  The specification struct or nil if not found
  """
  @spec find_specification(atom()) :: struct() | nil
  def find_specification(name) do
    GenServer.call(__MODULE__, {:find, :specifications, name})
  end
  
  @doc """
  List all registered operators.
  
  ## Returns
  
  A map of operator names to modules
  """
  @spec list_operators() :: %{optional(atom()) => module()}
  def list_operators do
    GenServer.call(__MODULE__, {:list, :operators})
  end
  
  @doc """
  List all registered providers.
  
  ## Returns
  
  A map of provider names to modules
  """
  @spec list_providers() :: %{optional(atom()) => module()}
  def list_providers do
    GenServer.call(__MODULE__, {:list, :providers})
  end
  
  @doc """
  List all registered specifications.
  
  ## Returns
  
  A map of specification names to structs
  """
  @spec list_specifications() :: %{optional(atom()) => struct()}
  def list_specifications do
    GenServer.call(__MODULE__, {:list, :specifications})
  end
  
    @doc """
  Register a model.
  
  ## Parameters
  
  - name: The name of the model (e.g., "openai/gpt-4")
  - model_info: Map containing model information
  
  ## Returns
  
  `:ok` if successful
  """
  @spec register_model(String.t(), map()) :: :ok
  def register_model(name, model_info) do
    GenServer.call(__MODULE__, {:register, :models, name, model_info})
  end

  @doc """
  Find a model by name.
  
  ## Parameters
  
  - name: The name of the model to find (e.g., "openai/gpt-4")
  
  ## Returns
  
  The model info map or nil if not found
  """
  @spec find_model(String.t()) :: map() | nil
  def find_model(name) do
    GenServer.call(__MODULE__, {:find, :models, name})
  end

  @doc """
  List all registered models.
  
  ## Returns
  
  A map of model names to info maps
  """
  @spec list_models() :: %{optional(String.t()) => map()}
  def list_models do
    GenServer.call(__MODULE__, {:list, :models})
  end

  @doc """
  Initiates auto-discovery of components in the configured discovery paths.
  
  ## Returns
  
  `:ok` if the discovery process was initiated
  """
  @spec discover() :: :ok
  def discover do
    GenServer.cast(__MODULE__, :perform_discovery)
  end

  @doc """
  Set the discovery paths for auto-discovery.
  
  ## Parameters
  
  - paths: List of paths to scan for components
  
  ## Returns
  
  `:ok` if successful
  """
  @spec set_discovery_paths([String.t()]) :: :ok
  def set_discovery_paths(paths) do
    GenServer.call(__MODULE__, {:set_discovery_paths, paths})
  end

  # Server callbacks
  
  @impl true
  def handle_call({:register, type, name, module}, _from, state) do
    Logger.debug("Registering #{type} '#{name}': #{inspect(module)}")
    updated_state = put_in(state, [type, name], module)
    {:reply, :ok, updated_state}
  end
  
  @impl true
  def handle_call({:find, type, name}, _from, state) do
    result = Map.get(state[type], name)
    {:reply, result, state}
  end
  
  @impl true
  def handle_call({:list, type}, _from, state) do
    {:reply, state[type], state}
  end

  @impl true
  def handle_call({:set_discovery_paths, paths}, _from, state) do
    {:reply, :ok, %{state | discovery_paths: paths}}
  end

  @impl true
  def handle_cast(:perform_discovery, state) do
    updated_state = perform_discovery(state)
    {:noreply, updated_state}
  end

  @impl true
  def handle_info(:perform_discovery, state) do
    updated_state = perform_discovery(state)
    {:noreply, updated_state}
  end

  # Private helper functions

  defp perform_discovery(state) do
    Logger.info("Starting auto-discovery of EmberEx components")
    
    # Discover operators with @ember_operator attribute
    operators = discover_components_by_attribute(:ember_operator, :operators)
    
    # Discover models with @ember_model attribute
    models = discover_models()
    
    # Discover providers with @ember_provider attribute
    providers = discover_components_by_attribute(:ember_provider, :providers)
    
    # Merge discovered components with existing state
    %{
      state |
      operators: Map.merge(state.operators, operators),
      models: Map.merge(state.models, models),
      providers: Map.merge(state.providers, providers)
    }
  end

  defp discover_components_by_attribute(attribute, _type) do
    Logger.debug("Discovering components with @#{attribute} attribute")
    
    # Get all modules in the application
    for {
      module, beam
    } <- :code.all_loaded(),
        is_atom(module),
        is_list(:beam_lib.chunks(beam, [:attributes])),
        {:ok, {_, attributes}} <- [:beam_lib.chunks(beam, [:attributes])],
        attribute_values <- Keyword.get_values(attributes, attribute),
        attribute_value <- List.wrap(attribute_values),
        module_name = get_module_name(module, attribute_value),
        reduce: %{} do
      acc -> Map.put(acc, module_name, module)
    end
  end

  defp discover_models do
    Logger.debug("Discovering models")
    
    # Get all modules with @ember_model attribute
    for {
      module, beam
    } <- :code.all_loaded(),
        is_atom(module),
        is_list(:beam_lib.chunks(beam, [:attributes])),
        {:ok, {_, attributes}} <- [:beam_lib.chunks(beam, [:attributes])],
        model_specs <- Keyword.get_values(attributes, :ember_model),
        model_spec <- List.wrap(model_specs),
        reduce: %{} do
      acc -> 
        case model_spec do
          {name, info} when is_binary(name) and is_map(info) ->
            Map.put(acc, name, info)
          _ ->
            Logger.warning("Invalid @ember_model format in #{inspect(module)}")
            acc
        end
    end
  end

  defp get_module_name(module, attribute_value) do
    case attribute_value do
      name when is_atom(name) -> name
      {name, _} when is_atom(name) -> name
      _ -> module_to_name(module)
    end
  end

  defp module_to_name(module) do
    module
    |> Atom.to_string()
    |> String.split(".")
    |> List.last()
    |> Macro.underscore()
    |> String.to_atom()
  end
end
