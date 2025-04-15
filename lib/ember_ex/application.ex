defmodule EmberEx.Application do
  @moduledoc """
  The EmberEx Application module.
  
  This module is responsible for starting the application and its supervision tree,
  including the registry, usage tracking services, JIT optimization system,
  and other core components.
  """
  
  use Application
  require Logger

  @doc """
  Start the EmberEx application.
  
  This function starts the supervision tree for the application,
  initializes the component registry, loads configuration
  from environment variables, and starts the JIT optimization system.
  """
  @spec start(any(), any()) :: {:ok, pid()} | {:error, term()}
  def start(_type, _args) do
    # Load configuration from environment variables
    EmberEx.Config.load_from_env()
    
    children = [
      # Start the Registry
      {EmberEx.Registry, []},

      # Start the UsageService if usage tracking is enabled
      usage_service_spec(),

      # Start the JIT Cache server
      {EmberEx.XCS.JIT.Cache, []},

      # Start Finch for outbound HTTP requests (Gemini integration)
      {Finch, name: EmberExFinch},

      # Start any other core services
      {EmberEx.Models.Config, []},
      # Start the A2A Plug.Cowboy server (DISABLED for local pipeline runs)
      # To enable the HTTP A2A server, uncomment the following line:
      # {Plug.Cowboy, scheme: :http, plug: EmberEx.A2ARouter, options: [port: 4100]}
    ]
    |> Enum.reject(&is_nil/1)

    opts = [strategy: :one_for_one, name: EmberEx.Supervisor]
    result = Supervisor.start_link(children, opts)
    
    # Initialize the component registry after startup
    Task.start(fn ->
      # Give the registry time to start
      Process.sleep(100)
      init_registry()
    end)
    
    result
  end
  
  @doc """
  Initialize the EmberEx framework after startup.
  
  This performs tasks that should happen after the supervision tree
  is up and running, such as discovering and registering components
  and starting the JIT optimization system.
  """
  @spec init_registry() :: :ok
  def init_registry do
    Logger.info("Initializing EmberEx component registry")
    
    # Discover providers and operators
    EmberEx.Discovery.discover_providers()
    EmberEx.Discovery.discover_operators()
    
    # Initialize the JIT optimization system
    case EmberEx.XCS.JIT.Init.start() do
      :ok ->
        Logger.info("JIT optimization system initialized")
      {:error, reason} ->
        Logger.error("Failed to initialize JIT optimization system: #{inspect(reason)}")
    end
    
    Logger.info("EmberEx initialization complete")
    :ok
  end
  
  # Only include the UsageService in the supervision tree if usage tracking is enabled
  defp usage_service_spec do
    if EmberEx.Config.get_in([:logging, :usage_tracking]) do
      {EmberEx.Models.UsageService, []}
    else
      nil
    end
  end
end
