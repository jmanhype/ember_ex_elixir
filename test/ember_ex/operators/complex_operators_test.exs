defmodule EmberEx.Operators.ComplexOperatorsTest do
  @moduledoc """
  Tests for complex operators in EmberEx.
  
  This module contains comprehensive tests for:
  - SequenceOperator
  - ParallelOperator
  
  It tests these operators in isolation and in combination to verify they work
  correctly in complex scenarios.
  """
  
  use ExUnit.Case, async: true
  
  alias EmberEx.Operators.{
    MapOperator,
    SequenceOperator,
    ParallelOperator
  }
  
  # Mock modules for testing
  # First we create a mock specification for our LLM tests
  defmodule TestSpecification do
    @moduledoc """
    Mock specification for testing LLMOperator.
    """
    
    defstruct [:prompt_template]
    
    def new(prompt_template) do
      %__MODULE__{prompt_template: prompt_template}
    end
  end
  
  # Implement the Specification protocol for our test specification
  defimpl EmberEx.Specifications.Specification, for: TestSpecification do
    def validate_input(_spec, input), do: {:ok, input}
    def validate_output(_spec, output), do: {:ok, output}
    def render_prompt(spec, _inputs), do: spec.prompt_template
    def input_schema(_spec), do: %{}
    def output_schema(_spec), do: %{}
  end

  # Mock module for creating test LLM callables
  defmodule TestModels do
    @moduledoc """
    Provides test model callables for LLMOperator tests.
    """
    
    @doc """
    Create a mock LLM callable that returns predictable responses.
    
    This follows the correct interface expected by the LLMOperator,
    which calls the model with a map of arguments, not just a prompt string.
    
    Args:
        response: The response string to return
        delay_ms: Optional delay to simulate processing time
        
    Returns:
        A function that takes model_args and returns {:ok, map()}
    """
    @spec create_test_model(String.t(), integer()) :: (map() -> {:ok, map()})
    def create_test_model(response, delay_ms \\ 0) do
      fn model_args ->
        if delay_ms > 0 do
          :timer.sleep(delay_ms)
        end
        
        # Extract the prompt from messages
        prompt = case get_in(model_args, [:messages]) do
          [%{content: content} | _] -> content
          _ -> "(no prompt)"
        end
        
        # Return a successful response in the format LLMOperator expects
        {:ok, %{response: "#{response} (prompt: #{String.slice(prompt, 0, 10)}...)"}} 
      end
    end
    
    @doc """
    Create a mock LLM callable that transforms the input in a predictable way.
    
    Args:
        transform_fn: Function that transforms the input prompt
        
    Returns:
        A function that applies the transform and returns {:ok, map()}
    """
    @spec create_transform_model((String.t() -> String.t())) :: (map() -> {:ok, map()})
    def create_transform_model(transform_fn) do
      fn model_args ->
        # Extract the prompt from messages
        prompt = case get_in(model_args, [:messages]) do
          [%{content: content} | _] -> content
          _ -> "(no prompt)"
        end
        
        # Apply the transform function
        result = transform_fn.(prompt)
        
        # Return the result in the expected format
        {:ok, %{response: result}}
      end
    end
  end
  
  describe "SequenceOperator" do
    test "executes operators in sequence" do
      # Create two simple map operators
      uppercase = MapOperator.new(&String.upcase/1, :text, :uppercase_text)
      reverse = MapOperator.new(&String.reverse/1, :uppercase_text, :reversed_text)
      
      # Create a sequence operator
      sequence = SequenceOperator.new([uppercase, reverse])
      
      # Test execution
      result = EmberEx.Operators.Operator.call(sequence, %{text: "hello world"})
      
      # Verify results directly
      assert is_map(result)
      assert Map.get(result, :text) == "hello world"
      assert Map.get(result, :uppercase_text) == "HELLO WORLD"
      assert Map.get(result, :reversed_text) == "DLROW OLLEH"
    end
    
    test "handles empty operator list" do
      # Create a sequence with no operators
      sequence = SequenceOperator.new([])
      
      # Test execution
      input = %{text: "hello"}
      result = EmberEx.Operators.Operator.call(sequence, input)
      
      # Should return input unchanged
      assert is_map(result)
      assert Map.get(result, :text) == "hello"
    end
    
    test "accumulates results from multiple operators" do
      op1 = MapOperator.new(fn _ -> %{one: 1} end, nil, nil)
      op2 = MapOperator.new(fn _ -> %{two: 2} end, nil, nil)
      op3 = MapOperator.new(fn %{one: one, two: two} -> %{sum: one + two} end, nil, nil)
      
      sequence = SequenceOperator.new([op1, op2, op3])
      
      result = EmberEx.Operators.Operator.call(sequence, %{})
      
      # Print the structure for debugging
      IO.inspect(result, label: "Sequence Operator Test Result")
      
      # Verify results are accumulated correctly
      assert Map.get(result, :one) == 1
      assert Map.get(result, :two) == 2
      assert Map.get(result, :sum) == 3
    end
    
    test "handles complex transformations" do
      # Initial transformer
      step1 = MapOperator.new(&String.upcase/1, :text, :step1)
      # Use the output of the first transformation
      step2 = MapOperator.new(&String.reverse/1, :step1, :result1)
      # Use original input again
      step3 = MapOperator.new(&String.downcase/1, :text, :step2)
      # Use the output of the third transformation
      step4 = MapOperator.new(
        fn text -> 
          String.split(text, "", trim: true)
          |> Enum.join(" ")
        end, 
        :step2, 
        :result2
      )
      
      # Create a sequence that applies all transformations
      sequence = SequenceOperator.new([step1, step2, step3, step4])
      
      # Execute with test input
      result = EmberEx.Operators.Operator.call(sequence, %{text: "Hello World"})
      
      # Output for debugging
      IO.inspect(result, label: "Result structure")
      
      # Verify all transformations are applied correctly
      assert Map.get(result, :text) == "Hello World"
      assert Map.get(result, :step1) == "HELLO WORLD"
      assert Map.get(result, :result1) == "DLROW OLLEH"
      assert Map.get(result, :step2) == "hello world"
      assert Map.get(result, :result2) == "h e l l o   w o r l d"
    end
  end
  
  describe "ParallelOperator" do
    test "executes operators in parallel" do
      # Create two map operators that will run in parallel
      uppercase = MapOperator.new(&String.upcase/1, :text, :uppercase)
      reverse = MapOperator.new(&String.reverse/1, :text, :reversed)
      
      # Create a parallel operator
      parallel = ParallelOperator.new([uppercase, reverse])
      
      # Test execution
      result = EmberEx.Operators.Operator.call(parallel, %{text: "hello"})
      
      # Verify both operations were performed
      assert Map.get(result, :text) == "hello"
      assert Map.get(result, :uppercase) == "HELLO"
      assert Map.get(result, :reversed) == "olleh"
    end
    
    test "handles conflicts in result keys" do
      # Create operators that will produce conflicting keys
      op1 = MapOperator.new(fn _ -> %{overlap: "from_op1", a: 1} end, nil, nil)
      op2 = MapOperator.new(fn _ -> %{overlap: "from_op2", b: 2} end, nil, nil)
      
      # Create a parallel operator
      parallel = ParallelOperator.new([op1, op2])
      
      # Test execution
      result = EmberEx.Operators.Operator.call(parallel, %{})
      
      # Last merged value should win for conflicts
      assert Map.get(result, :a) == 1
      assert Map.get(result, :b) == 2
      assert Map.get(result, :overlap) in ["from_op1", "from_op2"]
    end
    
    test "merges results correctly" do
      # Create operators that return maps with different keys
      op1 = MapOperator.new(fn _ -> %{a: 1, b: 2} end, nil, nil)
      op2 = MapOperator.new(fn _ -> %{c: 3, d: 4} end, nil, nil)
      
      # Create a parallel operator
      parallel = ParallelOperator.new([op1, op2])
      
      # Test execution
      result = EmberEx.Operators.Operator.call(parallel, %{original: "value"})
      
      # Verify all results are merged and original input is preserved
      assert Map.get(result, :original) == "value"
      assert Map.get(result, :a) == 1
      assert Map.get(result, :b) == 2
      assert Map.get(result, :c) == 3
      assert Map.get(result, :d) == 4
    end
    
    test "ParallelOperator preserves input values" do
      # Create operators that don't overwrite input
      op1 = MapOperator.new(fn _ -> %{a: 1} end, nil, nil)
      op2 = MapOperator.new(fn _ -> %{b: 2} end, nil, nil)
      
      # Create a parallel operator
      parallel = ParallelOperator.new([op1, op2])
      
      # Test with input that should be preserved
      original_input = %{input_key: "preserved", another_key: 123}
      result = EmberEx.Operators.Operator.call(parallel, original_input)
      
      # Debug the output structure
      IO.inspect(result, label: "ParallelOperator Result")
      
      # Simplified direct assertion since we've improved ParallelOperator.forward
      # The operator should now correctly preserve the input values
      assert Map.get(result, :input_key) == "preserved"
      assert Map.get(result, :another_key) == 123
      assert Map.get(result, :a) == 1
      assert Map.get(result, :b) == 2
    end
  end
  
  describe "Complex scenarios with SequenceOperator and ParallelOperator" do
    test "sequence of parallel operators" do
      # First parallel block
      parallel1 = ParallelOperator.new([
        MapOperator.new(&String.upcase/1, :text, :uppercase),
        MapOperator.new(&String.reverse/1, :text, :reversed)
      ])
      
      # Second parallel block
      parallel2 = ParallelOperator.new([
        MapOperator.new(&String.length/1, :uppercase, :uppercase_length),
        MapOperator.new(&String.length/1, :reversed, :reversed_length)
      ])
      
      # Sequence of parallel blocks
      sequence = SequenceOperator.new([parallel1, parallel2])
      
      # Test execution
      result = EmberEx.Operators.Operator.call(sequence, %{text: "hello"})
      
      # Debug the result structure
      IO.inspect(result, label: "Sequence of parallel operators result")
      
      # Verify results directly
      assert is_map(result), "Expected result to be a map"
      assert Map.get(result, :text) == "hello"
      assert Map.get(result, :uppercase) == "HELLO"
      assert Map.get(result, :reversed) == "olleh"
      assert Map.get(result, :uppercase_length) == 5
      assert Map.get(result, :reversed_length) == 5
    end
    
    test "parallel execution of sequences" do
      # First sequence
      seq1 = SequenceOperator.new([
        MapOperator.new(&String.upcase/1, :text, :uppercase),
        MapOperator.new(&String.reverse/1, :uppercase, :reversed_uppercase)
      ])
      
      # Second sequence
      seq2 = SequenceOperator.new([
        MapOperator.new(&String.downcase/1, :text, :lowercase),
        MapOperator.new(&String.reverse/1, :lowercase, :reversed_lowercase)
      ])
      
      # Parallel execution of sequences
      parallel = ParallelOperator.new([seq1, seq2])
      
      # Test execution
      result = EmberEx.Operators.Operator.call(parallel, %{text: "Hello"})
      
      # Verify results
      assert Map.get(result, :text) == "Hello"
      assert Map.get(result, :uppercase) == "HELLO"
      assert Map.get(result, :reversed_uppercase) == "OLLEH"
      assert Map.get(result, :lowercase) == "hello"
      assert Map.get(result, :reversed_lowercase) == "olleh"
    end
    
    test "complex transformation pipeline" do
      # Define a multi-stage pipeline with both parallel and sequential operations
      
      # Stage 1: Prepare input in parallel ways
      prepare_stage = ParallelOperator.new([
        MapOperator.new(&String.upcase/1, :input, :uppercase_input),
        MapOperator.new(&String.downcase/1, :input, :lowercase_input),
        MapOperator.new(&String.reverse/1, :input, :reversed_input)
      ])
      
      # Stage 2: Process each prepared input
      process_stage = SequenceOperator.new([
        # Process uppercase input
        MapOperator.new(
          fn %{uppercase_input: text} -> 
            %{uppercase_processed: String.replace(text, " ", "_")}
          end,
          nil,
          nil
        ),
        
        # Process lowercase input
        MapOperator.new(
          fn %{lowercase_input: text} -> 
            %{lowercase_processed: String.replace(text, " ", "-")}
          end,
          nil,
          nil
        ),
        
        # Process reversed input
        MapOperator.new(
          fn %{reversed_input: text} -> 
            %{reversed_processed: String.slice(text, 0, 5)}
          end,
          nil,
          nil
        )
      ])
      
      # Final stage: Combine results
      combine_stage = MapOperator.new(
        fn input -> 
          %{
            combined: input.uppercase_processed <> " | " <>
                     input.lowercase_processed <> " | " <>
                     input.reversed_processed
          }
        end,
        nil,
        nil
      )
      
      # Create the full pipeline
      pipeline = SequenceOperator.new([
        prepare_stage,
        process_stage,
        combine_stage
      ])
      
      # Test execution
      result = EmberEx.Operators.Operator.call(pipeline, %{input: "Hello World"})
      
      # Verify transformation worked correctly
      assert is_map(result)
      assert Map.get(result, :input) == "Hello World"
      assert Map.get(result, :uppercase_input) == "HELLO WORLD"
      assert Map.get(result, :lowercase_input) == "hello world"
      assert Map.get(result, :reversed_input) == "dlroW olleH"
      assert Map.get(result, :uppercase_processed) == "HELLO_WORLD"
      assert Map.get(result, :lowercase_processed) == "hello-world"
      assert Map.get(result, :reversed_processed) == "dlroW"
      assert Map.get(result, :combined) == "HELLO_WORLD | hello-world | dlroW"
    end
  end
  
  describe "Interaction with LLMOperator" do
    test "handles LLM operations in sequence" do
      # Create a test specification
      spec = TestSpecification.new("Translate the following text from {source_language} to {target_language}:\n\n{text}\n\nAlso detect the source language if set to 'auto'.")
      
      # Create test models
      summarize_model = TestModels.create_test_model("Summary")
      translate_model = TestModels.create_test_model("Translation")
      qa_model = TestModels.create_transform_model(fn prompt ->
        # Simple reversal as a test transform
        "Answer: " <> String.reverse(prompt)
      end)
      
      # Create operators for each task
      summarize_op = MapOperator.new(fn inputs ->
        {:ok, result} = summarize_model.(%{messages: [%{role: "user", content: "Summarize #{inputs.text}"}]})
        %{summary: result.response}
      end)
      
      translate_op = MapOperator.new(fn inputs ->
        {:ok, result} = translate_model.(%{messages: [%{role: "user", content: spec.prompt_template}]})
        %{translation: result.response}
      end)
      
      qa_op = MapOperator.new(fn inputs ->
        prompt = "Q: #{inputs.question} Context: #{inputs.text}"
        {:ok, result} = qa_model.(%{messages: [%{role: "user", content: prompt}]})
        %{answer: result.response}
      end)
      
      # Create a parallel operator for summarization and translation
      parallel = ParallelOperator.new([summarize_op, translate_op])
      
      # Create a sequence that does the parallel tasks then the QA
      sequence = SequenceOperator.new([
        parallel,
        qa_op
      ])
      
      # Test execution
      result = EmberEx.Operators.Operator.call(
        sequence, 
        %{text: "This is a test document", question: "What is this?"}
      )
      
      # Print the actual result structure for debugging
      IO.inspect(result, label: "LLM operator test result")
      
      # Verify operations were performed correctly
      assert is_map(result)
      assert Map.has_key?(result, :text)
      assert Map.has_key?(result, :question)
      assert Map.has_key?(result, :summary)
      assert Map.has_key?(result, :translation)
      assert Map.has_key?(result, :answer)
      
      # Verify content format
      assert String.contains?(Map.get(result, :summary), "Summary")
      assert String.contains?(Map.get(result, :translation), "Translation")
      assert String.starts_with?(Map.get(result, :answer), "Answer:")
    end
  end
end
