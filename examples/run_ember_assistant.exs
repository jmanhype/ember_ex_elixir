# Script to run the EmberEx Assistant with real OpenAI models
# This version creates a custom assistant that works with real OpenAI models

# Load required modules
Code.require_file(Path.join([Path.dirname(__DIR__), "lib", "ember_ex", "models", "models.ex"]))

defmodule FixedAssistant do
  @moduledoc """
  A fixed version of the assistant that works with real OpenAI models.
  Uses direct Instructor calls to bypass model resolution issues.
  """
  
  @doc """
  Creates and runs a simplified assistant that can handle various LLM tasks.
  """
  def run_all do
    # Ensure API key is set
    api_key = System.get_env("OPENAI_API_KEY")
    if is_nil(api_key) || api_key == "" do
      IO.puts("\n⚠️ Warning: OPENAI_API_KEY environment variable not set.")
      IO.puts("Setting a temporary API key for testing...")
      System.put_env("OPENAI_API_KEY", "YOUR_OPENAI_API_KEY_HERE")
    end
    
    # Start the application
    {:ok, _} = Application.ensure_all_started(:ember_ex)
    IO.puts("✅ Application started")
    
    # Create the assistant
    IO.puts("\n🚀 Testing EmberEx Assistant with Real Models")
    IO.puts("=========================================")
    
    # Test the assistant with various tasks
    test_summarization()
    test_question_answering()
    test_translation()
    
    IO.puts("\n✅ All tests completed!")
  end
  
  @doc """
  Test summarization functionality.
  """
  def test_summarization do
    IO.puts("\n📝 Testing summarization...")
    
    # Create a summarization map operator
    summarize_op = EmberEx.Operators.MapOperator.new_with_name(
      "summarize_op",
      nil,
      fn input ->
        model = "gpt-3.5-turbo-0125"
        
        # Use direct instructor call
        case Instructor.chat_completion(
          model: model,
          response_model: %{summary: :string},
          messages: [%{
            role: "user", 
            content: """
            Summarize the following text in a concise way:
            
            #{input.text}
            
            Provide a brief summary that captures the main points.
            """
          }]
        ) do
          {:ok, response} -> 
            %{summary: response.summary}
          {:error, reason} -> 
            raise "Model error: #{inspect(reason)}"
        end
      end
    )
    
    # Test input
    input = %{
      text: "The Ember framework is a powerful tool for building AI applications using Language Models (LLMs). It provides a structured approach to building LLM applications with features like operators, graphs, and execution engines. This port to Elixir aims to bring the same capabilities to the Elixir ecosystem while leveraging the functional programming paradigm and concurrency features of the BEAM virtual machine."
    }
    
    # Call the operator
    result = EmberEx.Operators.Operator.call(summarize_op, input)
    
    # Display the result
    IO.puts("Summary: #{result.summary}")
    
    result
  end
  
  @doc """
  Test question answering functionality.
  """
  def test_question_answering do
    IO.puts("\n❓ Testing question answering...")
    
    # Create a QA map operator
    qa_op = EmberEx.Operators.MapOperator.new_with_name(
      "qa_op",
      nil,
      fn input ->
        model = "gpt-3.5-turbo-0125"
        
        # Use direct instructor call
        case Instructor.chat_completion(
          model: model,
          response_model: %{answer: :string},
          messages: [%{
            role: "user", 
            content: """
            Answer this question based on the provided context.
            
            Context: #{input.context}
            
            Question: #{input.question}
            
            Provide a clear and concise answer based only on the information in the context.
            """
          }]
        ) do
          {:ok, response} -> 
            %{answer: response.answer}
          {:error, reason} -> 
            raise "Model error: #{inspect(reason)}"
        end
      end
    )
    
    # Test input
    input = %{
      context: "EmberEx is an Elixir port of the Ember framework, designed for building AI applications with language models. It features a graph-based execution engine that can run operations in parallel or sequentially. The framework includes operators like MapOperator, SequenceOperator, LLMOperator, and ParallelOperator.",
      question: "What is EmberEx and what types of operators does it include?"
    }
    
    # Call the operator
    result = EmberEx.Operators.Operator.call(qa_op, input)
    
    # Display the result
    IO.puts("Question: #{input.question}")
    IO.puts("Answer: #{result.answer}")
    
    result
  end
  
  @doc """
  Test translation functionality.
  """
  def test_translation do
    IO.puts("\n🌐 Testing translation...")
    
    # Create a translation map operator
    translate_op = EmberEx.Operators.MapOperator.new_with_name(
      "translate_op",
      nil,
      fn input ->
        model = "gpt-3.5-turbo-0125"
        
        # Use direct instructor call
        case Instructor.chat_completion(
          model: model,
          response_model: %{translation: :string},
          messages: [%{
            role: "user", 
            content: """
            Translate the following text from #{input.source_language} to #{input.target_language}:
            
            #{input.text}
            
            Provide only the translated text without any additional explanations.
            """
          }]
        ) do
          {:ok, response} -> 
            %{translation: response.translation}
          {:error, reason} -> 
            raise "Model error: #{inspect(reason)}"
        end
      end
    )
    
    # Test input
    input = %{
      text: "Hello, I would like to test the translation capabilities of the EmberEx framework with a real OpenAI model.",
      source_language: "English",
      target_language: "Spanish"
    }
    
    # Call the operator
    result = EmberEx.Operators.Operator.call(translate_op, input)
    
    # Display the result
    IO.puts("Original (#{input.source_language}): #{input.text}")
    IO.puts("Translated (#{input.target_language}): #{result.translation}")
    
    result
  end
end

# Run all the tests
FixedAssistant.run_all()
