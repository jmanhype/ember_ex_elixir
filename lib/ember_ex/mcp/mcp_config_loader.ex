defmodule EmberEx.MCP.McpConfigLoader do
  @moduledoc """
  Loads MCP server configuration from a JSON file (e.g., mcp_config.json).
  Provides a function to retrieve config for a given server name (e.g., "exa", "flux").
  """
  @type server_config :: %{
          command: String.t(),
          args: [String.t()],
          env: map() | nil
        }

  @spec get(String.t(), String.t()) :: server_config | nil
  def get(server_name, path \\ "~/.codeium/windsurf/mcp_config.json") do
    path = Path.expand(path)
    with {:ok, body} <- File.read(path),
         {:ok, %{"mcpServers" => servers}} <- Jason.decode(body),
         %{} = config <- Map.get(servers, server_name) do
      %{
        command: config["command"],
        args: config["args"] || [],
        env: config["env"] || %{}
      }
    else
      _ -> nil
    end
  end
end
