defmodule EmberEx.Operators.ExaOperator do
  @moduledoc """
  Operator for calling the Exa MCP server via the A2A protocol.
  This operator sends a search query to Exa and returns the results as a string or list.
  """
  require Logger

  @doc """
  Calls the Exa MCP server via stdio using the universal MCP client.
  Returns the Exa response as a string (the first answer) or an error string.
  """
  @spec call(any(), map()) :: String.t()
  @doc """
  Calls the Exa MCP server using the correct JSON-RPC 2.0 request format.

  Sends a search query to Exa via stdio using the universal MCP client, following the tools/call method and expected params.
  Waits up to 60 seconds for a response (increased timeout for slow/large queries).
  Returns the Exa response as a string (the first answer) or an error string.

  ## Parameters
  - _op: Operator struct (unused)
  - input: Map with :query (string)

  ## Returns
  - String.t(): The first result text, or an error string
  """
  @spec call(any(), %{query: String.t()}) :: String.t()
  def call(_op, %{query: query}) when is_binary(query) do
    require Logger
    config = EmberEx.MCP.McpConfigLoader.get("exa")
    if is_nil(config) do
      Logger.error("[ExaOperator] Could not load 'exa' config from ~/.codeium/windsurf/mcp_config.json")
      "[ExaOperator: Config not found]"
    else
      # Build JSON-RPC 2.0 request for Exa MCP
      payload = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => %{
          "name" => "search",
          "arguments" => %{"query" => query, "numResults" => 2},
          "_meta" => %{"progressToken" => 0}
        }
      }
      timeout = 60_000 # Increased to 60 seconds for slow or large Exa MCP queries
      Logger.info("[ExaOperator] Sending query to Exa MCP via stdio: #{query}")
      case EmberEx.MCP.McpStdioClient.call(
             binary: config.command,
             args: config.args,
             env: config.env,
             payload: payload,
             timeout: timeout
           ) do
        {:ok, %{"result" => %{"results" => [%{"text" => text} | _]}}} when is_binary(text) ->
          decode_exa_text_field(text)
        {:ok, %{"result" => %{"results" => []}}} ->
          "[ExaOperator: No results returned]"
        {:ok, %{"result" => %{"results" => [%{} | _] = results}}} ->
          # Fallback: return first available string field in the first result
          first = List.first(results)
          Enum.find_value(["text", "snippet", "title"], fn k -> Map.get(first, k) end) || "[ExaOperator: No text in result]"
        # NEW: Handle inner JSON string in 'content' field
        {:ok, %{"result" => %{"content" => [%{"text" => inner_json} | _]}}} when is_binary(inner_json) ->
          case Jason.decode(inner_json) do
            {:ok, %{"results" => [%{"text" => text} | _]}} -> text
            {:ok, %{"results" => []}} -> "[ExaOperator: No results returned (inner)]"
            {:ok, %{"results" => [%{} | _] = results}} ->
              first = List.first(results)
              Enum.find_value(["text", "snippet", "title"], fn k -> Map.get(first, k) end) || "[ExaOperator: No text in inner result]"
            _ -> "[ExaOperator: Could not decode inner JSON content]"
          end
        {:ok, resp} ->
          "[ExaOperator: Unexpected response: #{inspect(resp)}]"
        {:error, err} ->
          "[ExaOperator MCP error: #{err}]"
      end

    end
  end

  @doc """
  Returns an error string if the input is invalid.
  """
  @spec call(any(), any()) :: String.t()
  def call(_op, _), do: "[ExaOperator: Invalid input, expected %{query: query}]"

  @doc """
  Attempts to decode the Exa MCP 'text' field, which may itself be a JSON string.
  Returns the decoded map if successful, or the original string if not.
  """
  @spec decode_exa_text_field(String.t()) :: map() | String.t()
  defp decode_exa_text_field(text) when is_binary(text) do
    case Jason.decode(text) do
      {:ok, decoded} -> decoded
      _ -> text
    end
  end
end
