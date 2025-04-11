defmodule EmberEx.Models.Response do
  @moduledoc """
  A clean, consistent response object with enhanced functionality.
  
  This struct wraps a raw response and provides a more intuitive interface.
  """
  
  @typedoc "Response struct type"
  @type t :: %__MODULE__{
    content: String.t(),
    raw_response: term(),
    messages: list() | nil,
    metadata: map() | nil
  }
  
  defstruct [:content, :raw_response, :messages, :metadata]
  
  @doc """
  Return the response text when used as a string.
  
  ## Parameters
  
  - response: The response struct
  
  ## Returns
  
  The content of the response as a string
  """
  @spec to_string(t()) :: String.t()
  def to_string(%__MODULE__{content: content}), do: content
  
  @doc """
  Display a visual representation of this response.
  
  ## Parameters
  
  - response: The response struct
  
  ## Returns
  
  `:ok`
  """
  @spec visualize(t()) :: :ok
  def visualize(%__MODULE__{} = response) do
    IO.puts("\n--- Response ---")
    IO.puts(response.content)
    
    if response.metadata do
      IO.puts("\n--- Metadata ---")
      Enum.each(response.metadata, fn {k, v} ->
        IO.puts("#{k}: #{inspect(v)}")
      end)
    end
    
    IO.puts("---------------")
  end
end

defmodule EmberEx.Models do
  @moduledoc """
  Models API for Ember in Elixir.
  
  Provides a clean interface for interacting with language models from various providers,
  similar to the Python Ember implementation.
  """
  
  require Logger
  
  @typedoc "Function type for model callables"
  @type model_callable :: (String.t() -> EmberEx.Models.Response.t())
  
  # Define model provider configurations
  @providers %{
    "openai" => %{
      prefix: "openai:",
      # Default model versions for OpenAI
      model_versions: %{
        "gpt-3.5-turbo" => "gpt-3.5-turbo-0125",
        "gpt-4" => "gpt-4-0125-preview",
        "gpt-4o" => "gpt-4o-2024-05-13"
      }
    },
    "anthropic" => %{
      prefix: "anthropic:",
      model_versions: %{
        "claude-3" => "claude-3-opus-20240229"
      }
    },
    "deepmind" => %{
      prefix: "deepmind:",
      model_versions: %{}
    }
  }
  
  @doc """
  Create a model callable with the specified model ID and configuration.
  
  ## Parameters
  
  - model_id: The model identifier (e.g., "gpt-4o" or "openai:gpt-4o")
  - config: Optional configuration parameters
  
  ## Returns
  
  A callable function that takes a prompt and returns a response
  
  ## Examples
  
      iex> model = EmberEx.Models.model("gpt-4o")
      iex> response = model.("What is the capital of France?")
  """
  @spec model(String.t(), keyword()) :: model_callable()
  def model(model_id, config \\ []) do
    # Resolve the model ID for API calls
    {provider, api_model_id} = resolve_model_for_api(model_id)
    
    # Create a callable function that wraps the Instructor API
    fn prompt ->
      # Log the model call for debugging
      log_model_call(provider, api_model_id, prompt)
      
      # Create the final config with provider-specific options
      final_config = prepare_config_for_provider(provider, api_model_id, config)
      
      # Make the API call
      case do_api_call(prompt, final_config) do
        {:ok, response_data} -> 
          # Create a response struct
          %EmberEx.Models.Response{
            content: response_data.response,
            raw_response: response_data,
            metadata: %{
              provider: provider,
              model_id: api_model_id,
              timestamp: DateTime.utc_now()
            }
          }
        {:error, reason} -> 
          # Convert the error into a more helpful format
          handle_api_error(provider, api_model_id, reason)
      end
    end
  end
  
  @doc """
  Make the actual API call using Instructor.
  """
  @spec do_api_call(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def do_api_call(_prompt, config) do
    # Remove any provider prefix from the model name before API call
    model_name = extract_raw_model_name(Keyword.get(config, :model))
    
    # Create the final config with the correct model name
    final_config = Keyword.put(config, :model, model_name)
    
    # Make the API call
    Instructor.chat_completion(final_config)
  rescue
    e -> {:error, {e, __STACKTRACE__}}
  end
  
  @doc """
  Prepare the configuration for a specific provider.
  """
  @spec prepare_config_for_provider(String.t(), String.t(), keyword()) :: keyword()
  def prepare_config_for_provider(provider, model_id, user_config) do
    # Start with the base configuration
    base_config = [
      model: model_id,
      response_model: %{response: :string},
      messages: [%{role: "user", content: user_config[:prompt] || ""}],
      temperature: Keyword.get(user_config, :temperature, 0.7)
    ]
    
    # Add provider-specific configurations
    provider_config = case provider do
      "openai" -> [stream: false]
      "anthropic" -> []
      "deepmind" -> []
      _ -> []
    end
    
    # Merge with user config, ensuring user config takes precedence
    base_config
    |> Keyword.merge(provider_config)
    |> Keyword.merge(user_config)
  end
  
  @doc """
  Extract the raw model name without any provider prefix.
  """
  @spec extract_raw_model_name(String.t()) :: String.t()
  def extract_raw_model_name(model_id) do
    case model_id do
      "openai:" <> rest -> rest
      "anthropic:" <> rest -> rest
      "deepmind:" <> rest -> rest
      _ -> model_id
    end
  end
  
  @doc """
  Log model calls for debugging and telemetry.
  """
  @spec log_model_call(String.t(), String.t(), String.t()) :: :ok
  def log_model_call(provider, model_id, prompt) do
    truncated_prompt = if String.length(prompt) > 100, do: String.slice(prompt, 0, 97) <> "...", else: prompt
    Logger.debug("Calling #{provider} model #{model_id} with prompt: #{truncated_prompt}")
    :ok
  end
  
  @doc """
  Handle API errors with helpful messages.
  """
  @spec handle_api_error(String.t(), String.t(), term()) :: no_return()
  def handle_api_error(provider, model_id, reason) do
    # Format the error message based on the provider and error type
    error_message = case reason do
      {%{message: msg}, _} when is_binary(msg) ->
        "API Error (#{provider}): #{msg}"
      
      {exception, stacktrace} ->
        formatted_stack = Exception.format_stacktrace(stacktrace)
        "Exception calling #{provider} model #{model_id}: #{Exception.message(exception)}\n#{formatted_stack}"
      
      other ->
        "Unexpected error with #{provider} model #{model_id}: #{inspect(other)}"
    end
    
    # Log the error for debugging
    Logger.error(error_message)
    
    # Raise a runtime error
    raise RuntimeError, message: error_message
  end
  
  @doc """
  Create a model callable for use with LLMOperator.
  
  ## Parameters
  
  - model_name: The name of the model to use
  - opts: Additional options for the model
  
  ## Returns
  
  A callable function that takes a prompt and returns a response
  """
  @spec create_model_callable(String.t(), keyword()) :: (String.t() -> map())
  def create_model_callable(model_name, opts \\ []) do
    fn prompt ->
      try do
        # Create a model function and call it
        model_fn = model(model_name, opts)
        response = model_fn.(prompt)
        
        # Return the content as a map for compatibility with LLMOperator
        %{result: response.content}
      rescue
        e ->
          # Provide better error information
          Logger.error("Error in model callable: #{Exception.message(e)}")
          reraise e, __STACKTRACE__
      end
    end
  end
  
  @doc """
  Convert a simple model name to a fully-qualified ID if needed.
  This prepends the provider prefix if needed.
  
  ## Parameters
  
  - model_id: The model identifier
  
  ## Returns
  
  The fully-qualified model ID with provider prefix
  
  ## Examples
  
      iex> EmberEx.Models.resolve_model_id("gpt-4o")
      "openai:gpt-4o"
      
      iex> EmberEx.Models.resolve_model_id("openai:gpt-4o")
      "openai:gpt-4o"
  """
  @spec resolve_model_id(String.t()) :: String.t()
  def resolve_model_id("openai:" <> _ = model_id), do: model_id
  def resolve_model_id("anthropic:" <> _ = model_id), do: model_id
  def resolve_model_id("deepmind:" <> _ = model_id), do: model_id
  def resolve_model_id(model_id), do: "openai:#{model_id}"
  
  @doc """
  Resolve a model ID for API calls.
  This properly handles model versions and provider prefixes.
  
  ## Parameters
  
  - model_id: The model identifier
  
  ## Returns
  
  A tuple of {provider, api_model_id} where:
  - provider is the provider name (e.g., "openai")
  - api_model_id is the model ID to use with the API
  
  ## Examples
  
      iex> EmberEx.Models.resolve_model_for_api("gpt-3.5-turbo")
      {"openai", "gpt-3.5-turbo-0125"}
      
      iex> EmberEx.Models.resolve_model_for_api("openai:gpt-4")
      {"openai", "gpt-4-0125-preview"}
  """
  @spec resolve_model_for_api(String.t()) :: {String.t(), String.t()}
  def resolve_model_for_api(model_id) do
    # Handle provider-prefixed model IDs
    case model_id do
      "openai:" <> rest -> resolve_model_version("openai", rest)
      "anthropic:" <> rest -> resolve_model_version("anthropic", rest)
      "deepmind:" <> rest -> resolve_model_version("deepmind", rest)
      # No prefix, assume OpenAI
      _ -> resolve_model_version("openai", model_id)
    end
  end
  
  @doc """
  Resolve a specific model version based on provider and base model.
  
  ## Parameters
  
  - provider: The provider name
  - model_base: The base model ID
  
  ## Returns
  
  A tuple of {provider, specific_model_id}
  """
  @spec resolve_model_version(String.t(), String.t()) :: {String.t(), String.t()}
  def resolve_model_version(provider, model_base) do
    # Get provider configuration
    provider_config = Map.get(@providers, provider, %{model_versions: %{}})
    
    # Check if this is already a specific version (contains a dash and numbers)
    if is_specific_version?(model_base) do
      {provider, model_base}
    else
      # Try to get a specific version, or use the base model if no mapping exists
      specific_version = get_in(provider_config, [:model_versions, model_base]) || model_base
      {provider, specific_version}
    end
  end
  
  @doc """
  Check if a model ID is already a specific version.
  
  ## Parameters
  
  - model_id: The model ID to check
  
  ## Returns
  
  Boolean indicating if this is a specific version
  """
  @spec is_specific_version?(String.t()) :: boolean()
  def is_specific_version?(model_id) do
    # Pattern match for common version patterns like "-0125" or "-20240229"
    version_pattern = ~r/[-_]([\d]{4,8}|preview|dev)$/
    Regex.match?(version_pattern, model_id)
  end
end


