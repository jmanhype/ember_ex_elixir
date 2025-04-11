defmodule EmberEx.Models.Providers.Base do
  @moduledoc """
  Base provider behavior that all LLM provider implementations must follow.
  
  This module defines the contract for integrating different language model providers
  into the EmberEx framework, ensuring consistent behavior across providers.
  """
  
  @type model_id :: String.t()
  @type model_config :: map()
  @type model_request :: map()
  @type model_response :: map()
  @type usage_info :: %{
    prompt_tokens: non_neg_integer(),
    completion_tokens: non_neg_integer(),
    total_tokens: non_neg_integer()
  }
  
  @doc """
  Returns a list of model IDs supported by this provider.
  """
  @callback supported_models() :: [model_id()]
  
  @doc """
  Validates the configuration for a specific model.
  
  Returns either the validated configuration or an error message.
  """
  @callback validate_config(model_id(), model_config()) :: {:ok, model_config()} | {:error, String.t()}
  
  @doc """
  Generates text using the specified model and prompt.
  
  Returns either the generated text or an error.
  """
  @callback generate(model_id(), String.t(), model_config()) :: {:ok, String.t()} | {:error, any()}
  
  @doc """
  Generates a structured response using the specified model and request.
  
  Returns either the structured response or an error.
  """
  @callback generate_with_model(model_id(), model_request(), model_config()) :: 
    {:ok, model_response()} | {:error, any()}
  
  @doc """
  Calculates the cost of a model request/response pair.
  
  Returns the cost in USD.
  """
  @callback calculate_cost(model_id(), model_request(), model_response()) :: float()
  
  @doc """
  Extracts usage information from a model response.
  
  Returns a map containing token counts.
  """
  @callback extract_usage(model_id(), model_response()) :: usage_info() | nil
  
  @doc """
  Creates helper module for exposing a consistent interface across providers.
  """
  defmacro __using__(_opts) do
    quote do
      @behaviour EmberEx.Models.Providers.Base
      
      @impl true
      def extract_usage(_model_id, _response), do: nil
      
      defoverridable extract_usage: 2
    end
  end
end
