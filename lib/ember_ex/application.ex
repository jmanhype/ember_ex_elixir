defmodule EmberEx.Application do
  @moduledoc """
  The EmberEx Application module.
  
  This module is responsible for starting the application and its supervision tree,
  including the registry, usage tracking services, and other core components.
  """
  
  use Application
  require Logger

  @doc """
  Start the EmberEx application.
  
  This function starts the supervision tree for the application,
  initializes the component registry, and loads configuration
  from environment variables.
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
      
      # Start any other core services
      {EmberEx.Models.Config, []}
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
  is up and running, such as discovering and registering components.
  """
  @spec init_registry() :: :ok
  def init_registry do
    Logger.info("Initializing EmberEx component registry")
    
    # Discover providers and operators
    EmberEx.Discovery.discover_providers()
    EmberEx.Discovery.discover_operators()
    
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
