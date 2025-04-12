# Script to run the EmberEx Assistant with real OpenAI models
# This version modifies the Assistant module's graph directly to use the correct model format

defmodule AssistantFix do
  @moduledoc """
  Provides fixes for the EmberEx.Examples.Assistant module to work with real OpenAI models.
  """
  
  @doc """
  Creates a fixed version of the assistant graph that uses a working model ID.
  """
  def create_fixed_assistant_graph do
    # Set the working model
    working_model = "gpt-3.5-turbo-0125"
    IO.puts("🔧 Creating assistant with model: #{working_model}")
    
    # Create the operators for different tasks
    summarize_op = create_llm_operator(
      "summarize_op",
      "Summarize the following text in a concise way: {{text}}",
      working_model
    )
    
    qa_op = create_llm_operator(
      "qa_op",
      """
      Answer the following question based on this context:
      
      Context: {{context}}
      
      Question: {{question}}
      
      Answer:
      """,
      working_model
    )
    
    translate_op = create_llm_operator(
      "translate_op",
      """
      Translate the following text from {{source_language}} to {{target_language}}:
      
      {{text}}
      
      Translation:
      """,
      working_model
    )
    
    # Create a router to handle different task types
    router = EmberEx.Operators.MapOperator.new_with_name(
      "router",
      nil,
      fn input ->
        case input["type"] do
          "summarize" ->
            %{"text" => input["text"]}
            |> EmberEx.Operators.Operator.call(summarize_op)
            |> then(fn response -> 
              %{"summary" => response.content} 
            end)
          
          "qa" ->
            %{
              "context" => input["context"],
              "question" => input["question"]
            }
            |> EmberEx.Operators.Operator.call(qa_op)
            |> then(fn response -> 
              %{"answer" => response.content} 
            end)
          
          "translate" ->
            %{
              "text" => input["text"],
              "source_language" => input["source_language"],
              "target_language" => input["target_language"]
            }
            |> EmberEx.Operators.Operator.call(translate_op)
            |> then(fn response -> 
              %{"translation" => response.content} 
            end)
          
          _ ->
            %{"error" => "Unknown task type: #{input["type"]}"}
        end
      end
    )
    
    # Create the full graph with input/output mapping
    graph = EmberEx.XCS.Graph.new()
    |> EmberEx.XCS.Graph.add_node("input", EmberEx.Operators.PassthroughOperator.new())
    |> EmberEx.XCS.Graph.add_node("process", router)
    |> EmberEx.XCS.Graph.add_node("output", EmberEx.Operators.PassthroughOperator.new())
    |> EmberEx.XCS.Graph.add_edge("input", "process")
    |> EmberEx.XCS.Graph.add_edge("process", "output")
    
    graph
  end
  
  @doc """
  Creates an LLM operator with a direct model call to avoid model resolution issues.
  """
  def create_llm_operator(name, prompt_template, model_name) do
    # Create a callable function that bypasses model resolution
    model_fn = fn prompt ->
      # Direct call to Instructor
      Instructor.chat_completion(
        model: model_name,
        response_model: %{response: :string},
        messages: [%{role: "user", content: prompt}]
      )
      |> case do
        {:ok, %{response: response}} -> 
          %EmberEx.Models.Response{content: response, raw_response: response}
        {:error, reason} -> 
          raise "Model error: #{inspect(reason)}"
      end
    end
    
    # Create a specification
    spec = %EmberEx.Specifications.BasicSpecification{
      prompt_template: prompt_template
    }
    
    # Create the LLM operator
    EmberEx.Operators.LLMOperator.new_with_name(
      name,
      spec,
      model_fn
    )
  end
  
  @doc """
  Runs the fixed assistant with the given input.
  """
  def run(input) do
    graph = create_fixed_assistant_graph()
    results = EmberEx.XCS.Graph.execute(graph, %{"input" => input})
    results["output"]
  end
end

# Ensure API key is set
api_key = System.get_env("OPENAI_API_KEY")
if is_nil(api_key) || api_key == "" do
  IO.puts("\n⚠️ Warning: OPENAI_API_KEY environment variable not set.")
  IO.puts("Please set your API key before running this script:")
  IO.puts("export OPENAI_API_KEY=your_actual_api_key")
  IO.puts("\nExiting script as no API key is available.")
  System.halt(1)
end

# Start the application
Application.ensure_all_started(:ember_ex)
IO.puts("✅ Application started")

# Test the fixed assistant with various tasks
IO.puts("\n🚀 Testing Fixed Assistant")
IO.puts("=========================")

# Test summarization
summarize_input = %{
  "type" => "summarize", 
  "text" => "The Ember framework is a tool for building AI applications using Language Models. This port to Elixir aims to bring the same capabilities to the Elixir ecosystem while leveraging functional programming and concurrency features of the BEAM VM."
}

IO.puts("\n📝 Testing Fixed Assistant with summarize...")
summarize_result = AssistantFix.run(summarize_input)
IO.puts("Summary: #{summarize_result["summary"]}")

# Test question answering
qa_input = %{
  "type" => "qa",
  "context" => "EmberEx supports various language models including OpenAI, Anthropic, and DeepMind models. It provides a graph-based execution engine for AI workflows.",
  "question" => "What models does EmberEx support and what type of execution engine does it use?"
}

IO.puts("\n❓ Testing Fixed Assistant with qa...")
qa_result = AssistantFix.run(qa_input)
IO.puts("Answer: #{qa_result["answer"]}")

# Test translation
translate_input = %{
  "type" => "translate",
  "text" => "Hello, welcome to EmberEx! This is a test of the translation capabilities.",
  "source_language" => "English",
  "target_language" => "Spanish"
}

IO.puts("\n🌐 Testing Fixed Assistant with translate...")
translate_result = AssistantFix.run(translate_input)
IO.puts("Translation: #{translate_result["translation"]}")

IO.puts("\n✅ All tests completed successfully!")

# Provide some explanations about the fixes
IO.puts("\n🔍 Explanation of Fixes")
IO.puts("====================")
IO.puts("1. Created direct model callable functions that bypass the model resolution mechanism")
IO.puts("2. Used a specific working model version (gpt-3.5-turbo-0125)")
IO.puts("3. Constructed a custom graph that mimics the Assistant's functionality")
IO.puts("4. Used BasicSpecification instead of EctoSpecification to avoid schema validation issues")
IO.puts("\nThese fixes allow the Assistant to work with real OpenAI models without modifications to the core library.")
