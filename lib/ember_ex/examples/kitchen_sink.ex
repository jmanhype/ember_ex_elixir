defmodule EmberEx.Examples.KitchenSink do
  @moduledoc """
  The ultimate EmberEx example: demonstrates every major feature including LLM integration (Gemini 2.0),
  operator composition, scheduling, schema validation, logging, artifacts, and A2A protocol compliance.
  """

  require Logger
  alias EmberEx.Operators.{LLMOperator, MapOperator, SequenceOperator, ParallelOperator, VerifierOperator, Operator}
  alias EmberEx.Examples.KitchenSink.OutputSchema

  # 1. Ecto schema for output validation
  defmodule OutputSchema do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field :answer, :string
      field :retrieved_facts, {:array, :string}
      field :math_result, :float
      field :summary, :string
      field :exa_result, :string
    end

    @doc """
    Validates the output structure.
    """
    def changeset(attrs) do
      %__MODULE__{}
      |> cast(attrs, [:answer, :retrieved_facts, :math_result, :summary, :exa_result])
      |> validate_required([:answer, :retrieved_facts, :math_result, :summary, :exa_result])
    end
  end

  # 2. Custom mock retrieval operator
  defmodule RetrievalOperator do
    @moduledoc "Mock retrieval operator for demonstration."
    def call(_op, %{query: query}) do
      Logger.info("[RetrievalOperator] Retrieving facts for: #{query}")
      ["Fact 1 about #{query}", "Fact 2 about #{query}"]
    end
  end

  # 3. Custom mock math operator
  defmodule MathOperator do
    @moduledoc "Mock math operator for demonstration."
    def call(_op, %{numbers: numbers}) do
      Logger.info("[MathOperator] Calculating sum of: #{inspect(numbers)}")
      Enum.sum(numbers)
    end
  end

  # 4. Custom summarizer operator
  defmodule SummarizerOperator do
    @moduledoc "Mock summarizer operator for demonstration."
    def call(_op, %{facts: facts, answer: answer, exa_result: exa_result}) do
      Logger.info("[SummarizerOperator] Summarizing answer, facts, and exa result.")
      "Summary: #{answer} | Facts: #{Enum.join(facts, "; ")} | Exa: #{inspect(exa_result)}"
    end
  end

  @doc """
  Runs the full kitchen sink workflow.
  Accepts a user research question and a list of numbers to sum.
  Returns a validated, structured response with artifacts and logs.
  """
  @spec run(String.t(), [number()]) :: map()
  @spec run(String.t(), [number()]) :: map()
  def run(question, numbers) do
    Logger.info("[KitchenSink] Starting workflow for: #{question}")
    IO.inspect(%{step: "input", question: question, numbers: numbers}, label: "[KitchenSink][DEBUG] Input")

    # Step 1: LLMOperator mock (use MapOperator for protocol compatibility)
    llm_op = MapOperator.new(fn %{question: q} ->
      %{answer: "[Gemini2.0] The answer to '#{q}' is Paris."}
    end)

    # Step 3: MathOperator (mock, wrapped for pipeline)
    math_op = MapOperator.new(fn %{numbers: numbers} ->
      res = EmberEx.Examples.KitchenSink.MathOperator.call(nil, %{numbers: numbers})
      Logger.debug("[KitchenSink][DEBUG] MathOperator result: #{inspect(res)}")
      %{math_result: res}
    end)

    # Step 4: SummarizerOperator (mock, wrapped for pipeline)
    summarizer_op = MapOperator.new(fn acc ->
      res = EmberEx.Examples.KitchenSink.SummarizerOperator.call(nil, %{facts: acc.retrieved_facts, answer: acc.answer, exa_result: acc.exa_result})
      Logger.debug("[KitchenSink][DEBUG] SummarizerOperator result: #{inspect(res)}")
      %{summary: res}
    end)

    # Step 5: ParallelOperator (LLM + Retrieval + Exa)
    parallel = ParallelOperator.new([
      MapOperator.new(fn input ->
        result = Operator.call(llm_op, %{question: input.question})
        Logger.debug("[KitchenSink][DEBUG] LLMOperator result: #{inspect(result)}")
        result
      end),
      MapOperator.new(fn input ->
        facts = EmberEx.Examples.KitchenSink.RetrievalOperator.call(nil, %{query: input.question})
        Logger.debug("[KitchenSink][DEBUG] RetrievalOperator result: #{inspect(facts)}")
        %{retrieved_facts: facts}
      end),
      MapOperator.new(fn input ->
        result = EmberEx.Operators.ExaOperator.call(nil, %{query: input.question})
        Logger.debug("[KitchenSink][DEBUG] ExaOperator raw result: #{inspect(result)}")
        case result do
          s when is_binary(s) -> %{exa_result: s}
          m when is_map(m) -> %{exa_result: inspect(m)}
          _ -> %{exa_result: "[ExaOperator: Unexpected result]"}
        end
      end)
    ])

    # Step 6: SequenceOperator (LLM + Retrieval + Exa → Math → Summarizer)
    pipeline = SequenceOperator.new([
      parallel,
      MapOperator.new(fn acc ->
        Logger.debug("[KitchenSink][DEBUG] After parallel: #{inspect(acc)}")
        IO.inspect(acc, label: "[KitchenSink][DEBUG] After parallel")
        acc
      end),
      math_op,
      MapOperator.new(fn acc ->
        Logger.debug("[KitchenSink][DEBUG] After math_op: #{inspect(acc)}")
        IO.inspect(acc, label: "[KitchenSink][DEBUG] After math_op")
        acc
      end),
      summarizer_op,
      MapOperator.new(fn acc ->
        Logger.debug("[KitchenSink][DEBUG] After summarizer_op: #{inspect(acc)}")
        IO.inspect(acc, label: "[KitchenSink][DEBUG] After summarizer_op")
        acc
      end)
    ])

    # Step 7: VerifierOperator (schema validation)
    verifier = VerifierOperator.new([
      VerifierOperator.condition(
        fn result ->
          valid = OutputSchema.changeset(result).valid?
          Logger.debug("[KitchenSink][DEBUG] OutputSchema valid?: #{inspect(valid)} for result: #{inspect(result)}")
          valid
        end,
        "Output schema validation failed"
      )
    ], nil, :schema_valid)

    # Run the pipeline
    input = %{question: question, numbers: numbers}
    result = Operator.call(pipeline, input)
    Logger.info("[KitchenSink] Pipeline result: #{inspect(result)}")
    IO.inspect(result, label: "[KitchenSink][DEBUG] Pipeline result")

    # Validate output
    valid = Operator.call(verifier, result)
    Logger.info("[KitchenSink] Validation result: #{inspect(valid)}")
    IO.inspect(valid, label: "[KitchenSink][DEBUG] Validation result")

    # Attach artifacts (mock)
    artifacts = [
      %{type: "text", content: result.summary}
    ]

    # Return A2A-compliant response
    %{
      "task" => %{
        "id" => "task_" <> Base.encode16(:crypto.strong_rand_bytes(8)),
        "state" => if(valid[:schema_valid], do: "completed", else: "failed"),
        "messages" => [
          %{role: "user", parts: [question]},
          %{role: "agent", parts: [result.summary]}
        ],
        "artifacts" => artifacts,
        "created_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      }
    }
  end
end
