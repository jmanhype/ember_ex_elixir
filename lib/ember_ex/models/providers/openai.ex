defmodule EmberEx.Models.Providers.OpenAI do
  @moduledoc """
  OpenAI provider implementation for EmberEx.
  
  Integrates with OpenAI's API to provide access to GPT models.
  """
  
  use EmberEx.Models.Providers.Base
  
  require Logger
  
  @gpt_models [
    "gpt-3.5-turbo",
    "gpt-3.5-turbo-16k",
    "gpt-4",
    "gpt-4o",
    "gpt-4-turbo"
  ]
  
  @token_cost_per_1k %{
    "gpt-3.5-turbo" => %{input: 0.0015, output: 0.002},
    "gpt-3.5-turbo-16k" => %{input: 0.003, output: 0.004},
    "gpt-4" => %{input: 0.03, output: 0.06},
    "gpt-4o" => %{input: 0.01, output: 0.03},
    "gpt-4-turbo" => %{input: 0.01, output: 0.03}
  }
  
  @impl true
  def supported_models do
    @gpt_models
  end
  
  @impl true
  def validate_config(model_id, config) do
    cond do
      model_id not in @gpt_models ->
        {:error, "Unsupported model: #{model_id}"}
        
      is_nil(config[:api_key]) ->
        {:error, "OpenAI API key is required"}
        
      true ->
        {:ok, config}
    end
  end
  
  @impl true
  def generate(model_id, prompt, config) do
    with {:ok, config} <- validate_config(model_id, config) do
      request = %{
        messages: [
          %{role: "user", content: prompt}
        ],
        model: model_id,
        temperature: Map.get(config, :temperature, 0.7),
        max_tokens: Map.get(config, :max_tokens, 1000)
      }
      
      case send_request(request, config) do
        {:ok, response} ->
          content = extract_content(response)
          {:ok, content}
          
        {:error, _} = error ->
          error
      end
    end
  end
  
  @impl true
  def generate_with_model(model_id, request, config) do
    with {:ok, config} <- validate_config(model_id, config) do
      # Ensure model is set correctly in the request
      request = Map.put(request, :model, model_id)
      
      case send_request(request, config) do
        {:ok, _} = result ->
          result
          
        {:error, _} = error ->
          error
      end
    end
  end
  
  @impl true
  def calculate_cost(model_id, _request, response) do
    case extract_usage(model_id, response) do
      nil ->
        0.0
        
      %{prompt_tokens: input_tokens, completion_tokens: output_tokens} ->
        costs = Map.get(@token_cost_per_1k, model_id, %{input: 0.0, output: 0.0})
        
        input_cost = (input_tokens / 1000) * costs.input
        output_cost = (output_tokens / 1000) * costs.output
        
        input_cost + output_cost
    end
  end
  
  @impl true
  def extract_usage(_model_id, response) do
    case response do
      %{usage: usage} when is_map(usage) ->
        %{
          prompt_tokens: Map.get(usage, :prompt_tokens, 0),
          completion_tokens: Map.get(usage, :completion_tokens, 0),
          total_tokens: Map.get(usage, :total_tokens, 0)
        }
        
      _ ->
        nil
    end
  end
  
  # Private functions
  
  defp send_request(request, config) do
    api_key = config[:api_key]
    organization = config[:organization]
    
    headers = [
      {"Content-Type", "application/json"},
      {"Authorization", "Bearer #{api_key}"}
    ]
    
    # Add organization header if provided
    headers = if organization do
      [{"OpenAI-Organization", organization} | headers]
    else
      headers
    end
    
    body = Jason.encode!(request)
    
    case HTTPoison.post("https://api.openai.com/v1/chat/completions", body, headers) do
      {:ok, %{status_code: 200, body: response_body}} ->
        case Jason.decode(response_body, keys: :atoms) do
          {:ok, response} ->
            {:ok, response}
            
          {:error, error} ->
            Logger.error("Failed to decode OpenAI response: #{inspect(error)}")
            {:error, {:decode_error, error}}
        end
        
      {:ok, %{status_code: status_code, body: response_body}} ->
        error_message = case Jason.decode(response_body) do
          {:ok, %{"error" => error}} -> error
          _ -> response_body
        end
        
        Logger.error("OpenAI API error (#{status_code}): #{inspect(error_message)}")
        {:error, {:api_error, status_code, error_message}}
        
      {:error, error} ->
        Logger.error("OpenAI request failed: #{inspect(error)}")
        {:error, {:request_error, error}}
    end
  end
  
  defp extract_content(response) do
    case response do
      %{choices: [%{message: %{content: content}} | _]} ->
        content
        
      _ ->
        ""
    end
  end
end
