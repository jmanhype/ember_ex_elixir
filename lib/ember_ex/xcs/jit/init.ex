defmodule EmberEx.XCS.JIT.Init do
  @moduledoc """
  Initialization module for the JIT optimization system.
  
  Handles starting the JIT cache server and any other initialization
  needed by the JIT compilation system.
  """
  
  require Logger
  
  @doc """
  Starts the JIT optimization system.
  
  ## Returns
  
  `:ok` if started successfully, `{:error, reason}` otherwise
  """
  @spec start() :: :ok | {:error, term()}
  def start do
    Logger.info("Starting EmberEx JIT optimization system")
    
    case EmberEx.XCS.JIT.Cache.start_link() do
      {:ok, _pid} ->
        Logger.info("JIT cache server started successfully")
        :ok
        
      {:error, {:already_started, _}} ->
        Logger.info("JIT cache server already running")
        :ok
        
      {:error, reason} ->
        Logger.error("Failed to start JIT cache server: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
