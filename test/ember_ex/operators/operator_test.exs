defmodule EmberEx.Operators.OperatorTest do
  @moduledoc """
  Tests for the Operator protocol and implementations.
  """
  
  use ExUnit.Case, async: true
  
  alias EmberEx.Operators.MapOperator
  alias EmberEx.Operators.SequenceOperator
  alias EmberEx.Operators.BranchOperator
  alias EmberEx.Operators.RetryOperator
  
  if Mix.env() == :test do
    import ExUnit.CaptureLog
    
    if Version.match?(System.version(), ">= 1.8.0") do
      # Import these only if we're in Elixir 1.8+
      if Code.ensure_loaded?(ExUnit.Assertions) do
        import ExUnit.Assertions, only: [assert_receive: 2]
      end
    end
  end
  
  describe "MapOperator" do
    @tag :unit
    test "applies a function to input" do
      # Create a simple MapOperator that doubles a number
      double_fn = fn input -> %{value: input.value * 2} end
      operator = MapOperator.new(double_fn)
      
      # Call the operator
      result = EmberEx.Operators.Operator.call(operator, %{value: 5})
      
      # Check the result
      assert result.value == 10
    end
    
    @tag :unit
    test "handles map inputs" do
      # Create a MapOperator that concatenates strings
      concat_fn = fn input -> %{text: input.prefix <> input.suffix} end
      operator = MapOperator.new(concat_fn)
      
      # Call the operator
      result = EmberEx.Operators.Operator.call(operator, %{prefix: "Hello, ", suffix: "World!"})
      
      # Check the result
      assert result.text == "Hello, World!"
    end
  end
  
  describe "SequenceOperator" do
    @tag :unit
    test "executes operators in sequence" do
      # Create operators for the sequence
      double_op = MapOperator.new(fn input -> %{value: input.value * 2} end)
      add_10_op = MapOperator.new(fn input -> %{value: input.value + 10} end)
      
      # Create a sequence operator
      sequence_op = SequenceOperator.new([double_op, add_10_op])
      
      # Call the sequence operator
      result = EmberEx.Operators.Operator.call(sequence_op, %{value: 5})
      
      # Check the result: (5 * 2) + 10 = 20
      assert result.value == 20
    end
    
    @tag :unit
    test "handles empty sequence" do
      # Create an empty sequence operator
      sequence_op = SequenceOperator.new([])
      
      # Call the sequence operator
      result = EmberEx.Operators.Operator.call(sequence_op, %{value: 5})
      
      # Check that the input is returned unchanged
      assert result.value == 5
    end
  end
  
  describe "BranchOperator" do
    @tag :unit
    test "selects true branch when predicate is true" do
      # Create operators for the branches
      true_op = MapOperator.new(fn _ -> %{result: "true branch"} end)
      false_op = MapOperator.new(fn _ -> %{result: "false branch"} end)
      
      # Create a predicate function
      is_positive = fn input -> input.value > 0 end
      
      # Create a branch operator
      branch_op = BranchOperator.new(is_positive, true_op, false_op)
      
      # Call the branch operator with a positive value
      result = EmberEx.Operators.Operator.call(branch_op, %{value: 5})
      
      # Check that the true branch was selected
      assert result.result == "true branch"
    end
    
    @tag :unit
    test "selects false branch when predicate is false" do
      # Create operators for the branches
      true_op = MapOperator.new(fn _ -> %{result: "true branch"} end)
      false_op = MapOperator.new(fn _ -> %{result: "false branch"} end)
      
      # Create a predicate function
      is_positive = fn input -> input.value > 0 end
      
      # Create a branch operator
      branch_op = BranchOperator.new(is_positive, true_op, false_op)
      
      # Call the branch operator with a negative value
      result = EmberEx.Operators.Operator.call(branch_op, %{value: -5})
      
      # Check that the false branch was selected
      assert result.result == "false branch"
    end
  end
  
  describe "RetryOperator" do
    @tag :unit
    test "succeeds on first attempt" do
      # Create a simple operator that always succeeds
      success_op = MapOperator.new(fn input -> %{value: input.value + 1} end)
      
      # Wrap it in a retry operator
      retry_op = RetryOperator.new(success_op, max_attempts: 3)
      
      # Call the retry operator
      result = EmberEx.Operators.Operator.call(retry_op, %{value: 5})
      
      # Check the result
      assert result.value == 6
    end
    
    @tag :unit
    test "RetryOperator retries until success" do
      # Create a persistent term to track attempts across function calls
      :persistent_term.put(:retry_test_attempts, 0)
      
      # Create an operator that fails on the first attempt but succeeds on the second
      flaky_op = MapOperator.new(fn input ->
        # Get current attempt count and increment
        current_attempt = :persistent_term.get(:retry_test_attempts) + 1
        :persistent_term.put(:retry_test_attempts, current_attempt)
        
        IO.puts("Attempt #{current_attempt} in mapper function")
        
        if current_attempt == 1 do
          raise "Simulated failure"
        else
          # We're on the second attempt now
          %{value: input.value + 1}
        end
      end)
      
      # Wrap it in a retry operator
      retry_op = RetryOperator.new(flaky_op, max_attempts: 3, retry_delay_ms: 10)
      
      # Call the retry operator
      result = EmberEx.Operators.Operator.call(retry_op, %{value: 5})
      
      # Debug output
      IO.inspect(result, label: "RetryOperator test result")
      
      # Check the result
      assert result.value == 6
      assert result.attempts == 2
    end
    
    @tag :unit
    test "fails after max attempts" do
      # Create an operator that always fails
      failing_op = MapOperator.new(fn _ -> raise "Simulated failure" end)
      
      # Wrap it in a retry operator
      retry_op = RetryOperator.new(failing_op, max_attempts: 2, retry_delay_ms: 10)
      
      # Call the retry operator and expect it to fail
      assert_raise RuntimeError, "Simulated failure", fn ->
        EmberEx.Operators.Operator.call(retry_op, %{value: 5})
      end
    end
    
    @tag :unit
    test "respects should_retry_fn" do
      # Create an operator that raises different types of errors
      error_op = MapOperator.new(fn input ->
        case input.error_type do
          :retry -> raise "Retryable error"
          :no_retry -> raise "Non-retryable error"
          _ -> %{result: "success"}
        end
      end)
      
      # Create a should_retry_fn that only retries specific errors
      should_retry = fn error ->
        error_message = Exception.message(error)
        String.contains?(error_message, "Retryable")
      end
      
      # Wrap it in a retry operator
      retry_op = RetryOperator.new(error_op, 
        max_attempts: 3, 
        retry_delay_ms: 10,
        should_retry_fn: should_retry
      )
      
      # Test with a retryable error
      assert_raise RuntimeError, "Retryable error", fn ->
        EmberEx.Operators.Operator.call(retry_op, %{error_type: :retry})
      end
      
      # Test with a non-retryable error
      assert_raise RuntimeError, "Non-retryable error", fn ->
        EmberEx.Operators.Operator.call(retry_op, %{error_type: :no_retry})
      end
      
      # Test with no error
      result = EmberEx.Operators.Operator.call(retry_op, %{error_type: :none})
      assert result.result == "success"
    end
  end
end
