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
    ParallelOperator,
    LLMOperator
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
    def render_prompt(spec, inputs), do: spec.prompt_template
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
      
      # Verify results
      assert result.text == "hello world"
      assert result.uppercase_text == "HELLO WORLD"
      assert result.reversed_text == "DLROW OLLEH"
    end
    
    test "handles empty operator list" do
      # Create a sequence with no operators
      sequence = SequenceOperator.new([])
      
      # Test execution
      input = %{text: "hello"}
      result = EmberEx.Operators.Operator.call(sequence, input)
      
      # Should return input unchanged
      assert result == input
    end
    
    test "accumulates results correctly" do
      # Create operators that add new keys
      add_one = MapOperator.new(fn _ -> 1 end, nil, :one)
      add_two = MapOperator.new(fn _ -> 2 end, nil, :two)
      add_sum = MapOperator.new(
        fn %{one: one, two: two} -> one + two end,
        nil,
        :sum
      )
      
      # Create a sequence
      sequence = SequenceOperator.new([add_one, add_two, add_sum])
      
      # Test execution
      result = EmberEx.Operators.Operator.call(sequence, %{})
      
      # Verify all results are accumulated
      assert result.one == 1
      assert result.two == 2
      assert result.sum == 3
    end
    
    test "handles nested sequences" do
      # Inner sequence
      inner_seq = SequenceOperator.new([
        MapOperator.new(&String.upcase/1, :text, :uppercase),
        MapOperator.new(&String.reverse/1, :uppercase, :reversed)
      ])
      
      # Outer sequence
      outer_seq = SequenceOperator.new([
        inner_seq,
        MapOperator.new(fn %{reversed: rev} -> String.length(rev) end, nil, :length)
      ])
      
      # Test execution
      result = EmberEx.Operators.Operator.call(outer_seq, %{text: "hello"})
      
      # Verify results flow through all operators
      assert result.text == "hello"
      assert result.uppercase == "HELLO"
      assert result.reversed == "OLLEH"
      assert result.length == 5
    end
    
    test "handles errors gracefully" do
      # Create an operator that will raise an error
      error_op = MapOperator.new(fn _ -> raise "Test error" end, :text, :error_result)
      safe_op = MapOperator.new(&String.upcase/1, :text, :uppercase)
      
      # Test that the error propagates
      assert_raise RuntimeError, "Test error", fn ->
        SequenceOperator.new([safe_op, error_op]) 
        |> EmberEx.Operators.Operator.call(%{text: "hello"})
      end
      
      # Check that errors in the first operator also propagate
      assert_raise RuntimeError, "Test error", fn ->
        SequenceOperator.new([error_op, safe_op]) 
        |> EmberEx.Operators.Operator.call(%{text: "hello"})
      end
    end
  end
  
  describe "ParallelOperator" do
    test "executes operators in parallel" do
      # Create operators with delays to ensure they run in parallel
      # Using proper output keys to ensure we can merge results correctly
      op1 = MapOperator.new(fn _ -> 
        :timer.sleep(100)
        "result1" 
      end, nil, :output1)
      
      op2 = MapOperator.new(fn _ -> 
        :timer.sleep(100)
        "result2" 
      end, nil, :output2)
      
      # Create a parallel operator
      parallel = ParallelOperator.new([op1, op2])
      
      # Measure execution time
      start_time = :os.system_time(:millisecond)
      result = EmberEx.Operators.Operator.call(parallel, %{input: "test"})
      end_time = :os.system_time(:millisecond)
      
      # If truly parallel, should take ~100ms, not ~200ms
      assert (end_time - start_time) < 150
      
      # Results should contain both outputs merged with input
      assert result.input == "test"
      assert result.output1 == "result1"
      assert result.output2 == "result2"
    end
    
    test "handles empty operator list" do
      # Create a parallel operator with no operators
      parallel = ParallelOperator.new([])
      
      # Test execution
      input = %{text: "hello"}
      result = EmberEx.Operators.Operator.call(parallel, input)
      
      # Should return input unchanged
      assert result == input
    end
    
    test "merges results correctly" do
      # Create operators that return maps with different keys
      op1 = MapOperator.new(fn _ -> %{a: 1, b: 2} end, nil, nil)
      op2 = MapOperator.new(fn _ -> %{c: 3, d: 4} end, nil, nil)
      
      # Create a parallel operator
      parallel = ParallelOperator.new([op1, op2])
      
      # Test execution
      result = EmberEx.Operators.Operator.call(parallel, %{original: "value"})
      
      # Verify all results are merged
      assert result.original == "value"
      assert result.a == 1
      assert result.b == 2
      assert result.c == 3
      assert result.d == 4
    end
    
    test "handles conflicts in result keys" do
      # Create operators that return maps with overlapping keys
      op1 = MapOperator.new(fn _ -> %{a: 1, overlap: "from_op1"} end, nil, nil)
      op2 = MapOperator.new(fn _ -> %{b: 2, overlap: "from_op2"} end, nil, nil)
      
      # Create a parallel operator
      parallel = ParallelOperator.new([op1, op2])
      
      # Test execution
      result = EmberEx.Operators.Operator.call(parallel, %{})
      
      # Last merged value should win for conflicts
      assert result.a == 1
      assert result.b == 2
      assert result.overlap in ["from_op1", "from_op2"]
    end
    
    test "preserves input values" do
      # Create operators that don't overwrite input
      op1 = MapOperator.new(fn _ -> %{a: 1} end, nil, nil)
      op2 = MapOperator.new(fn _ -> %{b: 2} end, nil, nil)
      
      # Create a parallel operator
      parallel = ParallelOperator.new([op1, op2])
      
      # Test with input that should be preserved
      original_input = %{input_key: "preserved", another_key: 123}
      result = EmberEx.Operators.Operator.call(parallel, original_input)
      
      # Verify original input is preserved
      assert result.input_key == "preserved"
      assert result.another_key == 123
      assert result.a == 1
      assert result.b == 2
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
      
      # Verify all operations completed correctly
      assert result.text == "hello"
      assert result.uppercase == "HELLO"
      assert result.reversed == "olleh"
      assert result.uppercase_length == 5
      assert result.reversed_length == 5
    end
    
    test "parallel execution of sequences" do
      # First sequence
      sequence1 = SequenceOperator.new([
        MapOperator.new(&String.upcase/1, :text, :step1),
        MapOperator.new(&String.reverse/1, :step1, :result1)
      ])
      
      # Second sequence
      sequence2 = SequenceOperator.new([
        MapOperator.new(&String.downcase/1, :text, :step2),
        MapOperator.new(&String.capitalize/1, :step2, :result2)
      ])
      
      # Parallel execution of sequences
      parallel = ParallelOperator.new([sequence1, sequence2])
      
      # Test execution
      result = EmberEx.Operators.Operator.call(parallel, %{text: "Hello World"})
      
      # Verify all operations completed in both sequences
      assert result.text == "Hello World"
      assert result.step1 == "HELLO WORLD"
      assert result.result1 == "DLROW OLLEH"
      assert result.step2 == "hello world"
      assert result.result2 == "Hello world"
    end
    
    test "complex nested structure" do
      # Define a complex nested structure:
      # Sequence(
      #   op1,
      #   Parallel(
      #     Sequence(op2, op3),
      #     op4
      #   ),
      #   op5
      # )
      
      op1 = MapOperator.new(&String.upcase/1, :input, :uppercase)
      op2 = MapOperator.new(&String.reverse/1, :uppercase, :reversed)
      op3 = MapOperator.new(&String.length/1, :reversed, :length1)
      op4 = MapOperator.new(&String.length/1, :uppercase, :length2)
      op5 = MapOperator.new(
        fn %{length1: l1, length2: l2} -> l1 + l2 end,
        nil,
        :sum
      )
      
      # Build the nested structure
      inner_seq = SequenceOperator.new([op2, op3])
      parallel = ParallelOperator.new([inner_seq, op4])
      outer_seq = SequenceOperator.new([op1, parallel, op5])
      
      # Test execution
      result = EmberEx.Operators.Operator.call(outer_seq, %{input: "hello"})
      
      # Verify the complex flow worked correctly
      assert result.input == "hello"
      assert result.uppercase == "HELLO"
      assert result.reversed == "OLLEH"
      assert result.length1 == 5
      assert result.length2 == 5
      assert result.sum == 10
    end
    
    test "with simulated LLM operators" do
      # Create mock LLM callables
      summarize_model = TestModels.create_test_model("Summary")
      translate_model = TestModels.create_test_model("Translation")
      qa_model = TestModels.create_transform_model(fn prompt -> 
        "Answer: #{String.reverse(prompt)}" 
      end)
      
      # Create a simple function for output_key mapping
      output_key_fn = fn model_output, output_key ->
        %{output_key => model_output.response}
      end
      
      # Create LLM operators with our test specification
      summarize_op = MapOperator.new(fn _ ->
        {:ok, result} = summarize_model.(%{messages: [%{role: "user", content: "Summarize test document"}]})
        %{summary: result.response}
      end)
      
      translate_op = MapOperator.new(fn _ ->
        {:ok, result} = translate_model.(%{messages: [%{role: "user", content: "Translate test document"}]})
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
      
      # Verify all operations were performed
      assert result.text == "This is a test document"
      assert result.question == "What is this?"
      assert String.starts_with?(result.summary, "Summary")
      assert String.starts_with?(result.translation, "Translation")
      assert String.starts_with?(result.answer, "Answer:")
    end
  end
end
