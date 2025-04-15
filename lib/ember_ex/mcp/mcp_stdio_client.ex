defmodule EmberEx.MCP.McpStdioClient do
  @moduledoc """
  Universal client for communicating with any MCP-compatible server over stdio.
  Launches the MCP server as a subprocess, sends JSON requests, and parses JSON responses.
  Can be used by any operator that needs to talk to an MCP server via stdio (e.g., Exa, LLMs, etc).

  Usage:
    McpStdioClient.call(
      binary: "/usr/local/bin/exa-mcp-server",
      args: [],
      payload: %{action: "search", query: "What is the capital of France?"},
      timeout: 20_000
    )
  """

  require Logger
  @type payload :: map()
  @type response :: map() | {:error, String.t()}

  @spec call(
          binary: String.t(),
          args: [String.t()],
          payload: payload(),
          timeout: non_neg_integer()
        ) :: {:ok, response()} | {:error, String.t()}
  def call(opts) do
    binary = Keyword.fetch!(opts, :binary)
    args = Keyword.get(opts, :args, [])
    payload = Keyword.fetch!(opts, :payload)
    timeout = Keyword.get(opts, :timeout, 20_000)

    request =
      payload
      |> Jason.encode!()
      |> Kernel.<>("\n")

    env_map = Keyword.get(opts, :env, %{})
    env_list =
      env_map
      |> Enum.map(fn {k, v} -> {to_charlist(k), to_charlist(v)} end)

    IO.puts("[McpStdioClient DEBUG] Launching MCP server:")
    IO.inspect(binary, label: "[McpStdioClient DEBUG] binary")
    IO.inspect(args, label: "[McpStdioClient DEBUG] args")
    IO.inspect(env_list, label: "[McpStdioClient DEBUG] env_list")
    IO.inspect(File.cwd!(), label: "[McpStdioClient DEBUG] cwd")

    port =
      Port.open({:spawn_executable, binary}, [
        :binary,
        :exit_status,
        {:args, args},
        :use_stdio,
        :stderr_to_stdout,
        :hide,
        {:env, env_list}
      ])

    # Send the request
    # Send the request with a newline to ensure proper parsing by the MCP server
    Port.command(port, request)

    # Log all output for debugging
    Logger.debug("[McpStdioClient] Sent request: #{request}")
    receive_json_response(port, timeout, "")
  end

  @doc """
  Waits for and parses a valid JSON response from the MCP server, skipping non-JSON lines. Logs all server output for debugging.
  Handles timeouts and server exit statuses.
  """
  @doc """
  Waits for and parses a valid JSON response from the MCP server, buffering output to handle both compact and pretty-printed (multi-line) JSON. Logs all server output for debugging.
  Handles timeouts and server exit statuses.
  """
  @spec receive_json_response(port(), non_neg_integer(), String.t()) :: {:ok, map()} | {:error, String.t()}
  defp receive_json_response(port, timeout, buffer \\ "") do
    receive do
      {^port, {:data, data}} ->
        Logger.debug("[McpStdioClient] MCP server output: #{inspect(data)}")
        new_buffer = buffer <> data
        case extract_first_json(new_buffer) do
          {:ok, resp, _rest} ->
            Port.close(port)
            {:ok, resp}
          :incomplete ->
            receive_json_response(port, timeout, new_buffer)
          {:error, _} ->
            # If error, keep buffering (could be partial JSON)
            receive_json_response(port, timeout, new_buffer)
        end
      {^port, {:exit_status, status}} ->
        Port.close(port)
        {:error, "MCP server exited with status #{status}"}
    after
      timeout ->
        Port.close(port)
        {:error, "MCP server timed out after #{timeout} ms"}
    end
  end

  @doc """
  Attempts to extract and parse the first valid JSON object from the buffer.
  Returns {:ok, map, rest} if successful, :incomplete if more data is needed, or {:error, reason} if parsing fails for other reasons.
  """
  @spec extract_first_json(String.t()) :: {:ok, map(), String.t()} | :incomplete | {:error, any()}
  defp extract_first_json(buffer) do
    # Simple heuristic: find the first {...} block and try to decode it
    case Regex.run(~r/(\{(?:[^{}]|(?1))*\})/s, buffer) do
      [json_str | _] ->
        case Jason.decode(json_str) do
          {:ok, resp} -> {:ok, resp, String.replace_prefix(buffer, json_str, "")}
          _ -> :incomplete
        end
      _ -> :incomplete
    end
  end

end