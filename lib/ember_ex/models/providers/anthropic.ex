defmodule EmberEx.Models.Providers.Anthropic do
  @moduledoc """
  Anthropic Claude model provider integration for EmberEx.
  
  This module provides integration with Anthropic's Claude language models,
  supporting Claude-3 family models through their API.
  
  ## Authentication
  
  Requires an Anthropic API key set in the `ANTHROPIC_API_KEY` environment variable.
  
  ## Supported Models
  
  - `claude-3-opus`
  - `claude-3-sonnet`
  - `claude-3-haiku`
  - `claude-instant-1.2`
  - `claude-2.1`
  
  ## Features
  
  - Text generation with Claude models
  - Structured outputs through Instructor integration
  - Embeddings via the Anthropic API (when available)
  - Streaming responses
  - Tool use / function calling (for supported models)
  """
  
  @behaviour EmberEx.Models.Providers.Base
  
  alias EmberEx.Models.Usage
  require Logger
  
  @anthropic_api_url "https://api.anthropic.com/v1"
  @embedding_models ["claude-3-sonnet-embedding"]
  
  @impl true
  @doc """
  Create a completion with an Anthropic Claude model.
  
  ## Parameters
  
  - model_name: The name of the Claude model to use
  - options: Options for the completion request
    - messages: List of message maps with role and content
    - max_tokens: Maximum tokens to generate
    - temperature: Temperature for sampling (0.0 to 1.0)
    - top_p: Top-p sampling parameter
    - top_k: Top-k sampling parameter
    - stop: List of stop sequences
    - response_model: Schema for structured outputs (via Instructor)
    - stream: Whether to stream the response
    - stream_handler: Function to handle streaming chunks
    - tools: List of tools/functions to call
  
  ## Returns
  
  - `{:ok, response}` on success
  - `{:error, reason}` on failure
  
  ## Examples
  
      iex> EmberEx.Models.Providers.Anthropic.create_completion("claude-3-sonnet", %{
      ...>   messages: [
      ...>     %{role: "user", content: "Hello, Claude!"}
      ...>   ],
      ...>   max_tokens: 100
      ...> })
      {:ok, %{
        choices: [
          %{
            message: %{
              role: "assistant",
              content: "Hello! I'm Claude, an AI assistant created by Anthropic..."
            }
          }
        ],
        usage: %{
          prompt_tokens: 10,
          completion_tokens: 35,
          total_tokens: 45
        }
      }}
  """
  @spec create_completion(String.t(), map()) :: {:ok, map()} | {:error, any()}
  def create_completion(model_name, options) do
    api_key = get_api_key()
    
    # Handle structured schema output via Instructor
    if response_model = Map.get(options, :response_model) do
      create_structured_output(model_name, options, response_model, api_key)
    else
      # Regular completion
      create_standard_completion(model_name, options, api_key)
    end
  end
  
  @impl true
  @doc """
  Get embeddings for text using Anthropic's embedding models.
  
  ## Parameters
  
  - model_name: The name of the embedding model to use
  - text: The text to embed
  - options: Additional options for the embedding request
  
  ## Returns
  
  - `{:ok, embeddings}` on success
  - `{:error, reason}` on failure
  
  ## Examples
  
      iex> EmberEx.Models.Providers.Anthropic.get_embedding(
      ...>   "claude-3-sonnet-embedding",
      ...>   "Hello, world!"
      ...> )
      {:ok, [0.1, 0.2, 0.3, ...]}
  """
  @spec get_embedding(String.t(), String.t(), keyword()) :: {:ok, [float()]} | {:error, any()}
  def get_embedding(model_name, text, _options \\ []) do
    if model_name in @embedding_models do
      api_key = get_api_key()
      
      url = "#{@anthropic_api_url}/embeddings"
      headers = [
        {"x-api-key", api_key},
        {"anthropic-version", "2023-06-01"},
        {"content-type", "application/json"}
      ]
      
      body = Jason.encode!(%{
        model: model_name,
        input: text
      })
      
      case HTTPoison.post(url, body, headers) do
        {:ok, %{status_code: 200, body: response_body}} ->
          case Jason.decode(response_body) do
            {:ok, response} ->
              # Extract the embedding vector
              {:ok, response["embedding"]}
            
            {:error, _} = error ->
              Logger.error("Failed to parse Anthropic embedding response: #{inspect(error)}")
              error
          end
        
        {:ok, %{status_code: status_code, body: body}} ->
          error_message = "Anthropic API error (#{status_code}): #{body}"
          Logger.error(error_message)
          {:error, error_message}
        
        {:error, %HTTPoison.Error{reason: reason}} ->
          Logger.error("HTTP request failed: #{inspect(reason)}")
          {:error, reason}
      end
    else
      # Fallback to OpenAI for embeddings if Anthropic model not available
      Logger.warning("Unsupported Anthropic embedding model: #{model_name}. Falling back to OpenAI.")
      EmberEx.Models.Providers.OpenAI.get_embedding("text-embedding-3-small", text)
    end
  end

  @impl true
  @doc """
  Get supported sampling parameters for Anthropic models.
  
  ## Returns
  
  List of supported parameter names
  """
  @spec get_supported_sampling_parameters() :: [atom()]
  def get_supported_sampling_parameters do
    [:temperature, :top_p, :top_k, :stop]
  end
  
  @impl true
  @doc """
  List available models from Anthropic.
  
  ## Returns
  
  List of available model names
  """
  @spec list_available_models() :: [String.t()]
  def list_available_models do
    [
      "claude-3-opus",
      "claude-3-sonnet",
      "claude-3-haiku",
      "claude-instant-1.2",
      "claude-2.1"
    ] ++ @embedding_models
  end
  
  # Private helper functions
  
  defp get_api_key do
    System.get_env("ANTHROPIC_API_KEY") || 
      raise "ANTHROPIC_API_KEY environment variable is not set"
  end
  
  defp create_standard_completion(model_name, options, api_key) do
    url = "#{@anthropic_api_url}/messages"
    headers = [
      {"x-api-key", api_key},
      {"anthropic-version", "2023-06-01"},
      {"content-type", "application/json"}
    ]
    
    # Convert options to Anthropic API format
    request_body = %{
      model: model_name,
      messages: Map.get(options, :messages, []),
      max_tokens: Map.get(options, :max_tokens, 1024)
    }
    
    # Add optional parameters
    request_body = add_optional_params(request_body, options)
    
    # Handle streaming if requested
    if Map.get(options, :stream, false) do
      create_streaming_completion(url, headers, request_body, options)
    else
      # Regular synchronous completion
      case HTTPoison.post(url, Jason.encode!(request_body), headers) do
        {:ok, %{status_code: 200, body: response_body}} ->
          process_completion_response(response_body)
        
        {:ok, %{status_code: status_code, body: body}} ->
          error_message = "Anthropic API error (#{status_code}): #{body}"
          Logger.error(error_message)
          {:error, error_message}
        
        {:error, %HTTPoison.Error{reason: reason}} ->
          Logger.error("HTTP request failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end
  
  defp create_structured_output(model_name, options, response_model, api_key) do
    # Use Instructor to generate structured output
    instructor_options = Map.merge(options, %{
      model: model_name,
      response_model: response_model,
      provider: :anthropic,
      api_key: api_key
    })
    
    Instructor.complete(instructor_options)
  end
  
  defp create_streaming_completion(url, headers, request_body, options) do
    # Set streaming parameter
    request_body = Map.put(request_body, :stream, true)
    
    # Get the stream handler function
    stream_handler = Map.get(options, :stream_handler)
    
    # Start streaming request
    case HTTPoison.post(url, Jason.encode!(request_body), headers, stream_to: self()) do
      {:ok, %HTTPoison.AsyncResponse{id: _id}} ->
        # Process streaming response
        process_streaming_response(stream_handler)
      
      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("Streaming request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  defp process_streaming_response(stream_handler) do
    # Initial accumulated state
    initial_state = %{
      chunks: [],
      complete: false,
      content: "",
      error: nil
    }
    
    # Process streaming events
    final_state =
      Stream.unfold(initial_state, fn
        # When complete, end the stream
        %{complete: true} = _state ->
          nil
        
        # When error occurs, end the stream
        %{error: error} when not is_nil(error) ->
          nil
        
        # Process next chunk
        state ->
          receive do
            %HTTPoison.AsyncStatus{code: status_code} when status_code != 200 ->
              error = "Anthropic API stream error: HTTP #{status_code}"
              {nil, %{state | error: error, complete: true}}
            
            %HTTPoison.AsyncChunk{chunk: chunk} ->
              case process_stream_chunk(chunk, state, stream_handler) do
                {:ok, new_state} -> {chunk, new_state}
                {:error, error} -> {nil, %{state | error: error, complete: true}}
              end
            
            %HTTPoison.AsyncEnd{} ->
              {nil, %{state | complete: true}}
          after
            30_000 ->
              # Timeout after 30 seconds of no data
              {nil, %{state | error: :timeout, complete: true}}
          end
      end)
      |> Stream.run()
    
    # Return the final result
    if final_state.error do
      {:error, final_state.error}
    else
      # Construct final response from accumulated content
      response = %{
        choices: [
          %{
            message: %{
              role: "assistant",
              content: final_state.content
            }
          }
        ],
        usage: %{
          # Estimates since stream doesn't provide exact token counts
          prompt_tokens: 0,
          completion_tokens: 0,
          total_tokens: 0
        }
      }
      
      {:ok, response}
    end
  end
  
  defp process_stream_chunk(chunk, state, stream_handler) do
    # Each chunk in Anthropic's API is a data: prefix followed by JSON
    chunk_lines = String.split(chunk, "\n")
    
    # Process each line in the chunk
    Enum.reduce_while(chunk_lines, {:ok, state}, fn line, {:ok, acc_state} ->
      # Skip empty lines
      if String.trim(line) == "" do
        {:cont, {:ok, acc_state}}
      else
        # Extract JSON data from "data: {...}" format
        case Regex.run(~r/^data: (.+)$/, String.trim(line)) do
          [_, json_str] when json_str == "[DONE]" ->
            # End of stream marker
            {:cont, {:ok, %{acc_state | complete: true}}}
          
          [_, json_str] ->
            # Parse the JSON chunk
            case Jason.decode(json_str) do
              {:ok, chunk_data} ->
                # Process the chunk data
                process_chunk_data(chunk_data, acc_state, stream_handler)
              
              {:error, error} ->
                # JSON parsing error
                {:halt, {:error, "Failed to parse stream chunk: #{inspect(error)}"}}
            end
          
          nil ->
            # Line doesn't match expected format, might be an error message
            if String.contains?(line, "error") do
              {:halt, {:error, "Stream error: #{line}"}}
            else
              # Skip unrecognized line
              {:cont, {:ok, acc_state}}
            end
        end
      end
    end)
  end
  
  defp process_chunk_data(chunk_data, state, stream_handler) do
    # Extract content delta from chunk
    content_delta = get_content_delta(chunk_data)
    
    # Update accumulated content
    updated_content = state.content <> content_delta
    
    # Call user-provided stream handler if available
    if is_function(stream_handler) do
      stream_handler.(%{
        content: content_delta,
        full_content: updated_content,
        done: chunk_data["type"] == "message_stop"
      })
    end
    
    # Update state
    updated_state = %{
      state |
      chunks: [chunk_data | state.chunks],
      content: updated_content,
      complete: chunk_data["type"] == "message_stop"
    }
    
    {:cont, {:ok, updated_state}}
  end
  
  defp get_content_delta(chunk_data) do
    case chunk_data do
      %{"type" => "content_block_delta", "delta" => %{"text" => text}} ->
        text
      
      %{"type" => "message_delta", "delta" => %{"content" => content}} when is_list(content) ->
        # Handle structured content blocks
        Enum.map(content, fn
          %{"type" => "text", "text" => text} -> text
          _ -> ""
        end)
        |> Enum.join("")
      
      _ ->
        # No content in this chunk
        ""
    end
  end
  
  defp process_completion_response(response_body) do
    case Jason.decode(response_body) do
      {:ok, response} ->
        # Convert Anthropic response format to our standard format
        {:ok, %{
          choices: [
            %{
              message: %{
                role: "assistant",
                content: get_message_content(response)
              }
            }
          ],
          usage: %Usage{
            prompt_tokens: response["usage"]["input_tokens"] || 0,
            completion_tokens: response["usage"]["output_tokens"] || 0,
            total_tokens: (response["usage"]["input_tokens"] || 0) + (response["usage"]["output_tokens"] || 0)
          }
        }}
      
      {:error, _} = error ->
        Logger.error("Failed to parse Anthropic response: #{inspect(error)}")
        error
    end
  end
  
  defp get_message_content(response) do
    case response do
      %{"content" => content} when is_list(content) ->
        # Handle structured content blocks
        Enum.map(content, fn
          %{"type" => "text", "text" => text} -> text
          _ -> ""
        end)
        |> Enum.join("")
      
      %{"content" => content} when is_binary(content) ->
        content
      
      _ ->
        ""
    end
  end
  
  defp add_optional_params(request_body, options) do
    request_body
    |> maybe_add_param(:temperature, options)
    |> maybe_add_param(:top_p, options)
    |> maybe_add_param(:top_k, options)
    |> maybe_add_param(:stop_sequences, options, :stop)
    |> maybe_add_tools(options)
  end
  
  defp maybe_add_param(request_body, param_name, options, source_name \\ nil) do
    source_name = source_name || param_name
    
    case Map.get(options, source_name) do
      nil -> request_body
      value -> Map.put(request_body, param_name, value)
    end
  end
  
  defp maybe_add_tools(request_body, options) do
    case Map.get(options, :tools) do
      nil -> request_body
      [] -> request_body
      tools -> 
        # Convert tools to Anthropic format
        anthropic_tools = Enum.map(tools, &convert_tool_format/1)
        Map.put(request_body, :tools, anthropic_tools)
    end
  end
  
  defp convert_tool_format(tool) do
    %{
      "name" => tool["name"] || tool[:name],
      "description" => tool["description"] || tool[:description],
      "input_schema" => tool["parameters"] || tool[:parameters]
    }
  end
end
