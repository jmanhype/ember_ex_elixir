# Script to run the EmberEx Assistant with real OpenAI models
# Applies necessary fixes to make the Assistant work correctly

# Set the OpenAI API key
# IMPORTANT: Replace this with your actual API key before running
# or set it in your environment variables using:
# export OPENAI_API_KEY=your_actual_key
api_key = System.get_env("OPENAI_API_KEY") || "ENV_VAR_NOT_SET"
System.put_env("OPENAI_API_KEY", api_key)

# Start the application
Application.ensure_all_started(:ember_ex)

# Patch the model resolution to use a known working model
defmodule AssistantPatch do
  @moduledoc """
  Patches for running the Assistant module with real OpenAI models.
  """
  
  @doc """
  Apply the necessary patches to make the Assistant work with OpenAI.
  """
  def apply_patches do
    # Patch the model creation function to use a working model version
    patch_model_function()
    IO.puts("✅ Model function patched")
  end
  
  @doc """
  Create a patched version of the model function.
  """
  def patch_model_function do
    # Store the original function
    original_model_fn = &EmberEx.Models.model/2
    
    # Define our patched function
    patched_model_fn = fn model_id, config ->
      # Use a specific model version that we know works
      working_model = "gpt-3.5-turbo-0125"
      IO.puts("🔄 Model request: #{model_id} -> using #{working_model}")
      
      # Create a function that directly calls Instructor without using model resolution
      fn prompt ->
        Instructor.chat_completion(
          [
            model: working_model,  # Use the working model directly
            response_model: %{response: :string},
            messages: [%{role: "user", content: prompt}],
            temperature: Keyword.get(config, :temperature, 0.7)
          ] ++ config
        )
        |> case do
          {:ok, %{response: response}} -> 
            %EmberEx.Models.Response{content: response, raw_response: response}
          {:error, reason} -> 
            raise "Model error: #{inspect(reason)}"
        end
      end
    end
    
    # Replace the function for this session
    :meck.new(EmberEx.Models, [:passthrough])
    :meck.expect(EmberEx.Models, :model, patched_model_fn)
    
    # Return the original function in case we need to restore it
    original_model_fn
  end
end

# Apply the patches
try do
  AssistantPatch.apply_patches()
rescue
  e ->
    IO.puts("⚠️ Could not apply patches: #{Exception.message(e)}")
    IO.puts("This may be due to :meck not being available. We'll continue without patches.")
end

# Test functions for the Assistant
defmodule AssistantTest do
  @moduledoc """
  Tests for the EmberEx.Examples.Assistant module.
  """
  
  @doc """
  Run a simplified version of the Assistant.
  """
  def run_simple do
    IO.puts("\n🚀 Running simplified Assistant...")
    
    # Create a custom assistant using MapOperator
    create_simple_assistant = fn ->
      model_name = "gpt-3.5-turbo-0125"
      
      # Create operators for each capability
      summarize_op = EmberEx.Operators.MapOperator.new_with_name(
        "summarize_op",
        nil,
        fn input ->
          Instructor.chat_completion(
            model: model_name,
            response_model: %{response: :string},
            messages: [%{
              role: "user", 
              content: "Summarize this text in a concise way: #{input.text}"
            }]
          )
          |> case do
            {:ok, %{response: response}} -> 
              %{"summary" => response}
            {:error, reason} -> 
              raise "Model error: #{inspect(reason)}"
          end
        end
      )
      
      qa_op = EmberEx.Operators.MapOperator.new_with_name(
        "qa_op",
        nil,
        fn input ->
          Instructor.chat_completion(
            model: model_name,
            response_model: %{response: :string},
            messages: [%{
              role: "user", 
              content: """
              Answer this question based on the provided context.
              
              Context: #{input.context}
              
              Question: #{input.question}
              """
            }]
          )
          |> case do
            {:ok, %{response: response}} -> 
              %{"answer" => response}
            {:error, reason} -> 
              raise "Model error: #{inspect(reason)}"
          end
        end
      )
      
      translate_op = EmberEx.Operators.MapOperator.new_with_name(
        "translate_op",
        nil,
        fn input ->
          Instructor.chat_completion(
            model: model_name,
            response_model: %{response: :string},
            messages: [%{
              role: "user", 
              content: """
              Translate the following text from #{input.source_language} to #{input.target_language}:
              
              #{input.text}
              """
            }]
          )
          |> case do
            {:ok, %{response: response}} -> 
              %{"translation" => response}
            {:error, reason} -> 
              raise "Model error: #{inspect(reason)}"
          end
        end
      )
      
      # Create a routing operator that selects the appropriate operator
      router = EmberEx.Operators.MapOperator.new_with_name(
        "router",
        nil,
        fn input ->
          case input.task do
            "summarize" -> 
              result = EmberEx.Operators.Operator.call(summarize_op, input)
              %{"output" => result["summary"]}
              
            "qa" -> 
              result = EmberEx.Operators.Operator.call(qa_op, input)
              %{"output" => result["answer"]}
              
            "translate" -> 
              result = EmberEx.Operators.Operator.call(translate_op, input)
              %{"output" => result["translation"]}
              
            _ -> 
              %{"output" => "Unsupported task type: #{input.task}"}
          end
        end
      )
      
      # Return the router as our simple assistant
      router
    end
    
    # Create the assistant
    assistant = create_simple_assistant.()
    
    # Test summarization
    summarize_input = %{
      task: "summarize",
      text: "The Ember framework is a powerful tool for building AI applications using Language Models (LLMs). It provides a structured approach to building LLM applications with features like operators, graphs, and execution engines. This port to Elixir aims to bring the same capabilities to the Elixir ecosystem while leveraging the functional programming paradigm and concurrency features of the BEAM virtual machine."
    }
    
    IO.puts("\n📝 Testing summarization...")
    summarize_result = EmberEx.Operators.Operator.call(assistant, summarize_input)
    IO.puts("Summary: #{summarize_result["output"]}")
    
    # Test question answering
    qa_input = %{
      task: "qa",
      context: "EmberEx is an Elixir port of the Ember framework, designed for building AI applications with language models. It features a graph-based execution engine that can run operations in parallel or sequentially. The framework includes operators like MapOperator, SequenceOperator, LLMOperator, and ParallelOperator.",
      question: "What is EmberEx and what operators does it include?"
    }
    
    IO.puts("\n❓ Testing question answering...")
    qa_result = EmberEx.Operators.Operator.call(assistant, qa_input)
    IO.puts("Answer: #{qa_result["output"]}")
    
    # Test translation
    translate_input = %{
      task: "translate",
      text: "Hello, I would like to test the translation capabilities of the EmberEx framework.",
      source_language: "English",
      target_language: "French"
    }
    
    IO.puts("\n🌐 Testing translation...")
    translate_result = EmberEx.Operators.Operator.call(assistant, translate_input)
    IO.puts("Translation: #{translate_result["output"]}")
    
    IO.puts("\n✅ Simplified Assistant tested successfully!")
  end
  
  @doc """
  Test the actual EmberEx.Examples.Assistant module.
  """
  def run_real_assistant do
    IO.puts("\n🚀 Testing the EmberEx.Examples.Assistant module...")
    
    # Test summarization
    summarize_input = %{
      "type" => "summarize", 
      "text" => "The Ember framework is a tool for building AI applications using Language Models. This port to Elixir aims to bring the same capabilities to the Elixir ecosystem while leveraging functional programming."
    }
    
    IO.puts("\n📝 Testing Assistant.run with summarize...")
    try do
      summarize_result = EmberEx.Examples.Assistant.run(summarize_input)
      IO.puts("Summary: #{summarize_result["summary"]}")
      :ok
    rescue
      e -> 
        IO.puts("❌ Error running summarization: #{Exception.message(e)}")
        :error
    end
    
    # Test question answering
    qa_input = %{
      "type" => "qa",
      "context" => "EmberEx supports various language models including OpenAI, Anthropic, and DeepMind models.",
      "question" => "What models does EmberEx support?"
    }
    
    IO.puts("\n❓ Testing Assistant.run with qa...")
    try do
      qa_result = EmberEx.Examples.Assistant.run(qa_input)
      IO.puts("Answer: #{qa_result["answer"]}")
      :ok
    rescue
      e -> 
        IO.puts("❌ Error running question answering: #{Exception.message(e)}")
        :error
    end
    
    # Test translation
    translate_input = %{
      "type" => "translate",
      "text" => "Hello, welcome to EmberEx!",
      "source_language" => "English",
      "target_language" => "Spanish"
    }
    
    IO.puts("\n🌐 Testing Assistant.run with translate...")
    try do
      translate_result = EmberEx.Examples.Assistant.run(translate_input)
      IO.puts("Translation: #{translate_result["translation"]}")
      :ok
    rescue
      e -> 
        IO.puts("❌ Error running translation: #{Exception.message(e)}")
        :error
    end
  end
end

# First run the simplified assistant
AssistantTest.run_simple()

# Then try the actual Assistant module
IO.puts("\n===========================================")
IO.puts("Next, we'll try the actual Assistant module")
IO.puts("===========================================")
AssistantTest.run_real_assistant()
