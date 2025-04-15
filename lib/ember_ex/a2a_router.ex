defmodule EmberEx.A2ARouter do
  @moduledoc """
  Plug router for A2A protocol endpoints, including the agent card.
  """
  use Plug.Router

  plug :match
  plug :dispatch

  @doc """
  Serves the agent card for A2A discovery.
  """
  get "/.well-known/agent.json" do
    agent_card = %{
      name: "Ember X",
      version: "0.1.0",
      capabilities: ["run_task", "schedule_job"],
      endpoint: "http://localhost:4100/a2a"
    }

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(agent_card))
  end

  @doc """
  Handles A2A task creation (POST /a2a/tasks/send).
  Accepts a JSON payload, dispatches to the appropriate Ember X function based on action,
  assigns a task ID, and returns a compliant response.

  ## Supported actions
    - "run_task": expects `operator` (module name as string) and `inputs` (map)
    - "schedule_job": expects `graph`, `inputs` (map), and uses SequentialScheduler as demo
  """

  post "/a2a/tasks/send" do
    {:ok, body, _conn} = Plug.Conn.read_body(conn)
    with {:ok, params} <- Jason.decode(body) do
      task_id = "task_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
      action = params["action"]
      user_msg = params["messages"] || []
      created_at = DateTime.utc_now() |> DateTime.to_iso8601()
      try do
        {result, agent_msg} =
          case action do
            "run_task" ->
              operator_mod = params["operator"] |> String.to_existing_atom()
              inputs = params["inputs"] || %{}
              output = apply(operator_mod, :call, [operator_mod, inputs])
              {output, %{"text" => "Operator executed: #{inspect(output)}"}}
            "schedule_job" ->
              graph = params["graph"]
              inputs = params["inputs"] || %{}
              # Example: use SequentialScheduler for demonstration
              output = EmberEx.XCS.Schedulers.SequentialScheduler.execute(%{}, graph, inputs)
              {output, %{"text" => "Job scheduled: #{inspect(output)}"}}
            "gemini" ->
              prompt = params["prompt"] || extract_prompt_from_messages(user_msg)
              gemini_response = call_gemini(prompt)
              {gemini_response, %{"text" => gemini_response}}
            _ ->
              raise "Unknown action: #{inspect(action)}"
          end
        response = %{
          "task" => %{
            "id" => task_id,
            "state" => "completed",
            "messages" => [
              %{"role" => "user", "parts" => user_msg},
              %{"role" => "agent", "parts" => [agent_msg]}
            ],
            "artifacts" => [],
            "created_at" => created_at
          }
        }
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(response))
      rescue
        e ->
          error_response = %{
            "task" => %{
              "id" => task_id,
              "state" => "failed",
              "messages" => [
                %{"role" => "user", "parts" => user_msg},
                %{"role" => "agent", "parts" => [%{"text" => "Error: #{Exception.message(e)}"}]}
              ],
              "artifacts" => [],
              "created_at" => created_at
            }
          }
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(500, Jason.encode!(error_response))
      end
    else
      _ ->
        send_resp(conn, 400, Jason.encode!(%{"error" => "Invalid JSON"}))
    end
  end

  @doc """
  Calls the Gemini API with the given prompt and returns the response text.
  """
  @spec call_gemini(String.t()) :: String.t()
  defp call_gemini(prompt) when is_binary(prompt) do
    api_key = System.get_env("GEMINI_API_KEY")
    if is_nil(api_key) do
      raise "Gemini API key not set in GEMINI_API_KEY environment variable"
    end
    url = "https://generativelanguage.googleapis.com/v1/models/gemini-2.0-flash:generateContent?key=#{api_key}"
    headers = [
      {"Content-Type", "application/json"}
    ]
    body = Jason.encode!(%{"contents" => [%{"parts" => [%{"text" => prompt}]}]})
    case Finch.build(:post, url, headers, body)
         |> Finch.request(EmberExFinch) do
      {:ok, %Finch.Response{status: 200, body: resp_body}} ->
        case Jason.decode(resp_body) do
          {:ok, %{"candidates" => [%{"content" => %{"parts" => [%{"text" => text} | _]}} | _]}} ->
            text
          {:ok, decoded} ->
            inspect(decoded)
          _ ->
            "[Gemini: Unable to parse response]"
        end
      {:ok, %Finch.Response{status: status, body: resp_body}} ->
        "[Gemini error #{status}: #{resp_body}]"
      {:error, err} ->
        "[Gemini HTTP error: #{inspect(err)}]"
    end
  end

  @doc """
  Extracts a prompt string from A2A user messages, if present.
  """
  @spec extract_prompt_from_messages(list()) :: String.t()
  defp extract_prompt_from_messages(messages) when is_list(messages) do
    messages
    |> Enum.map(fn
      %{"text" => text} -> text
      %{"parts" => parts} when is_list(parts) ->
        Enum.map(parts, fn part -> part["text"] || "" end) |> Enum.join(" ")
      _ -> ""
    end)
    |> Enum.join(" ")
    |> String.trim()
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end
end
