defmodule EmberEx.Registry do
  @moduledoc """
  Registry for EmberEx components.
  
  Provides a central registry for discovering and accessing operators,
  model providers, and other extension components.
  """
  
  use GenServer
  require Logger
  
  @type component_type :: :operators | :providers | :specifications
  @type registry :: %{
    operators: %{optional(atom()) => module()},
    providers: %{optional(atom()) => module()},
    specifications: %{optional(atom()) => struct()}
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
  def init(_opts) do
    {:ok, %{
      operators: %{},
      providers: %{},
      specifications: %{}
    }}
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
end
