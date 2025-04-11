defmodule EmberEx.Examples.Assistant do
  @moduledoc """
  Example implementation of an AI assistant using EmberEx.
  
  This module demonstrates how to use EmberEx to build a simple AI assistant
  that can answer questions, summarize text, and translate content.
  """
  
  alias EmberEx.Specifications.EctoSpecification
  alias EmberEx.Operators.{LLMOperator, MapOperator}
  alias EmberEx.Examples.Schemas.{
    SummarizeInput, SummarizeOutput,
    QAInput, QAOutput,
    TranslateInput, TranslateOutput
  }
  alias EmberEx.XCS.Graph
  
  @doc """
  Create a summarization operator.
  
  ## Parameters
  
  - model_name: The name of the model to use (default: "openai/gpt-4")
  
  ## Returns
  
  A new LLMOperator for summarization
  
  ## Examples
  
      iex> summarize_op = EmberEx.Examples.Assistant.create_summarize_operator()
      iex> result = EmberEx.Operators.Operator.call(summarize_op, %{
      ...>   text: "Long text to summarize...",
      ...>   max_length: 50
      ...> })
      %{summary: "Concise summary..."}
  """
  @spec create_summarize_operator(String.t()) :: EmberEx.Operators.Operator.t()
  def create_summarize_operator(model_name \\ "openai/gpt-4") do
    # Create a specification for summarization
    spec = EctoSpecification.new(
      "Summarize the following text in {max_length} words or less:\n\n{text}",
      SummarizeInput,
      SummarizeOutput
    )
    
    # Create a model callable
    model = EmberEx.Models.create_model_callable(model_name)
    
    # Create the operator
    LLMOperator.new(spec, model)
  end
  
  @doc """
  Create a question answering operator.
  
  ## Parameters
  
  - model_name: The name of the model to use (default: "openai/gpt-4")
  
  ## Returns
  
  A new LLMOperator for question answering
  
  ## Examples
  
      iex> qa_op = EmberEx.Examples.Assistant.create_qa_operator()
      iex> result = EmberEx.Operators.Operator.call(qa_op, %{
      ...>   question: "What is the capital of France?",
      ...>   context: "France is a country in Western Europe. Its capital is Paris."
      ...> })
      %{answer: "Paris", confidence: 0.95}
  """
  @spec create_qa_operator(String.t()) :: EmberEx.Operators.Operator.t()
  def create_qa_operator(model_name \\ "openai/gpt-4") do
    # Create a specification for question answering
    spec = EctoSpecification.new(
      "Answer the following question based on the provided context:\n\nContext: {context}\n\nQuestion: {question}\n\nProvide your answer and a confidence score between 0 and 1.",
      QAInput,
      QAOutput
    )
    
    # Create a model callable
    model = EmberEx.Models.create_model_callable(model_name)
    
    # Create the operator
    LLMOperator.new(spec, model)
  end
  
  @doc """
  Create a translation operator.
  
  ## Parameters
  
  - model_name: The name of the model to use (default: "openai/gpt-4")
  
  ## Returns
  
  A new LLMOperator for translation
  
  ## Examples
  
      iex> translate_op = EmberEx.Examples.Assistant.create_translate_operator()
      iex> result = EmberEx.Operators.Operator.call(translate_op, %{
      ...>   text: "Hello, world!",
      ...>   target_language: "French"
      ...> })
      %{translated_text: "Bonjour, monde!", detected_language: "English"}
  """
  @spec create_translate_operator(String.t()) :: EmberEx.Operators.Operator.t()
  def create_translate_operator(model_name \\ "openai/gpt-4") do
    # Create a specification for translation
    spec = EctoSpecification.new(
      "Translate the following text from {source_language} to {target_language}:\n\n{text}\n\nAlso detect the source language if set to 'auto'.",
      TranslateInput,
      TranslateOutput
    )
    
    # Create a model callable
    model = EmberEx.Models.create_model_callable(model_name)
    
    # Create the operator
    LLMOperator.new(spec, model)
  end
  
  @doc """
  Create a multi-function assistant using a graph.
  
  This creates a graph with multiple operators for different functions
  and uses a router to direct the input to the appropriate operator.
  
  ## Returns
  
  A graph that can be executed with different types of inputs
  
  ## Examples
  
      iex> graph = EmberEx.Examples.Assistant.create_assistant_graph()
      iex> result = EmberEx.XCS.Graph.execute(graph, %{
      ...>   "input" => %{
      ...>     type: "summarize",
      ...>     text: "Long text to summarize...",
      ...>     max_length: 50
      ...>   }
      ...> })
  """
  @spec create_assistant_graph() :: EmberEx.XCS.Graph.t()
  def create_assistant_graph do
    # Create the operators
    summarize_op = create_summarize_operator()
    qa_op = create_qa_operator()
    translate_op = create_translate_operator()
    
    # Create a router operator that directs input to the appropriate operator
    router_op = create_router_operator()
    
    # Create a graph
    Graph.new(%{name: "Assistant"})
    
    # Add nodes
    |> Graph.add_node("input", router_op, %{description: "Input router"})
    |> Graph.add_node("summarize", summarize_op, %{description: "Summarization"})
    |> Graph.add_node("qa", qa_op, %{description: "Question answering"})
    |> Graph.add_node("translate", translate_op, %{description: "Translation"})
    |> Graph.add_node("output", create_output_operator(), %{description: "Output formatter"})
    
    # Add edges
    |> Graph.add_edge("input", "summarize", "summarize_input", "input")
    |> Graph.add_edge("input", "qa", "qa_input", "input")
    |> Graph.add_edge("input", "translate", "translate_input", "input")
    |> Graph.add_edge("summarize", "output", nil, "result")
    |> Graph.add_edge("qa", "output", nil, "result")
    |> Graph.add_edge("translate", "output", nil, "result")
  end
  
  # Create a router operator that directs input to the appropriate operator
  defp create_router_operator do
    MapOperator.new_with_name("router", nil, fn input ->
      # Safely get the type with a default
      type = Map.get(input, :type)
      
      if type == nil do
        # If no type is specified, try to infer from available keys
        cond do
          Map.has_key?(input, :text) && Map.has_key?(input, :max_length) ->
            # Likely a summarize request
            %{
              summarize_input: %{
                text: input.text,
                max_length: input.max_length
              },
              qa_input: nil,
              translate_input: nil
            }
            
          Map.has_key?(input, :question) && Map.has_key?(input, :context) ->
            # Likely a QA request
            %{
              summarize_input: nil,
              qa_input: %{
                question: input.question,
                context: input.context
              },
              translate_input: nil
            }
            
          Map.has_key?(input, :text) && Map.has_key?(input, :target_language) ->
            # Likely a translation request
            %{
              summarize_input: nil,
              qa_input: nil,
              translate_input: %{
                text: input.text,
                source_language: Map.get(input, :source_language, "auto"),
                target_language: input.target_language
              }
            }
            
          true ->
            # Default to empty outputs if we can't determine the type
            %{
              summarize_input: nil,
              qa_input: nil,
              translate_input: nil
            }
        end
      else
        # Process based on explicit type
        case type do
          "summarize" ->
            %{
              summarize_input: %{
                text: input.text,
                max_length: Map.get(input, :max_length, 100)
              },
              qa_input: nil,
              translate_input: nil
            }
            
          "qa" ->
            %{
              summarize_input: nil,
              qa_input: %{
                question: input.question,
                context: input.context
              },
              translate_input: nil
            }
            
          "translate" ->
            %{
              summarize_input: nil,
              qa_input: nil,
              translate_input: %{
                text: input.text,
                source_language: Map.get(input, :source_language, "auto"),
                target_language: input.target_language
              }
            }
            
          _ ->
            raise "Unknown input type: #{type}"
        end
      end
    end)
  end
  
  # Create an output operator that formats the output
  defp create_output_operator do
    MapOperator.new_with_name("output_formatter", nil, fn input ->
      # Try to get the result from either atom or string key
      result = cond do
        is_map_key(input, :result) -> input.result
        is_map_key(input, "result") -> input["result"]
        true -> raise "No result found in input: #{inspect(input)}"
      end
      
      # Return the result
      %{
        result: result,
        timestamp: DateTime.utc_now() |> DateTime.to_string()
      }
    end)
  end
  
  @doc """
  Run the assistant with the given input.
  
  ## Parameters
  
  - input: The input to the assistant
  
  ## Returns
  
  The result of the assistant
  
  ## Examples
  
      iex> EmberEx.Examples.Assistant.run(%{
      ...>   type: "summarize",
      ...>   text: "Long text to summarize...",
      ...>   max_length: 50
      ...> })
      %{
      ...>   result: %{summary: "Concise summary..."},
      ...>   timestamp: "2023-01-01 12:00:00Z"
      ...> }
  """
  @spec run(map()) :: map()
  def run(input) do
    # Create the graph
    graph = create_assistant_graph()
    
    # Execute the graph
    results = Graph.execute(graph, %{"input" => input})
    
    # Return the output
    results["output"]
  end
end
