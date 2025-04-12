defmodule EmberEx.XCS.JIT.Strategies.TraceStrategyTest do
  @moduledoc """
  Tests for the trace-based JIT optimization strategy.
  """
  
  use ExUnit.Case, async: true
  
  alias EmberEx.Operators.{MapOperator, SequenceOperator, Operator}
  alias EmberEx.XCS.JIT.Strategies.TraceStrategy
  
  describe "name/0" do
    test "returns the correct strategy name" do
      assert TraceStrategy.name() == "trace"
    end
  end
  
  describe "analyze/2" do
    test "analyzes simple operators correctly" do
      # Create a simple operator that handles map inputs properly
      op = MapOperator.new(fn x -> %{value: x.value * 2} end) 
      inputs = %{value: 5}
      
      # Analyze the operator
      result = TraceStrategy.analyze(op, inputs)
      
      # Verify the result has the expected structure
      assert is_map(result)
      assert is_integer(result.score)
      assert is_binary(result.rationale)
      assert is_list(result.execution_trace)
      assert is_list(result.hot_paths)
      assert is_list(result.optimization_targets)
    end
    
    test "analyzes sequence operators correctly" do
      # Create a sequence of operations
      op = SequenceOperator.new([
        MapOperator.new(fn x -> %{value: x.value * 2} end),
        MapOperator.new(fn x -> %{value: x.value + 10} end)
      ])
      inputs = %{value: 5}
      
      # Analyze the operator
      result = TraceStrategy.analyze(op, inputs)
      
      # Verify the result has the expected structure
      assert is_map(result)
      assert is_integer(result.score)
      assert is_binary(result.rationale)
      assert is_list(result.execution_trace)
      assert is_list(result.hot_paths)
      assert is_list(result.optimization_targets)
      
      # Sequence should have execution trace with multiple entries
      assert length(result.execution_trace) > 0
    end
    
    test "produces scores within expected range" do
      # Create a complex operator with repeated patterns
      repeated_op = MapOperator.new(fn x -> x end)
      sequence_ops = List.duplicate(repeated_op, 5)
      op = SequenceOperator.new(sequence_ops)
      
      # Analyze the operator
      result = TraceStrategy.analyze(op, %{value: 1})
      
      # Score should be between 0 and 100
      assert result.score >= 0
      assert result.score <= 100
    end
  end
  
  describe "compile/3" do
    test "returns original operator for low scores" do
      op = MapOperator.new(fn x -> x * 2 end)
      inputs = %{value: 5}
      
      # Create a mock analysis with low score
      analysis = %{
        score: 10,
        rationale: "Not worth optimizing",
        execution_trace: [],
        hot_paths: [],
        optimization_targets: []
      }
      
      # Compile with the analysis
      result = TraceStrategy.compile(op, inputs, analysis)
      
      # Should return the original operator
      assert result == op
    end
    
    test "optimizes operators with high scores" do
      # Create a sequence of operations
      op = SequenceOperator.new([
        MapOperator.new(fn x -> %{value: x.value * 2} end),
        MapOperator.new(fn x -> %{value: x.value + 10} end)
      ])
      inputs = %{value: 5}
      
      # Create a mock analysis with high score
      analysis = %{
        score: 80,
        rationale: "Good optimization potential",
        execution_trace: [%{target: op, inputs: inputs, result: %{value: 20}, execution_time: 1.0, path: []}],
        hot_paths: [[:prepare_inputs, :compute, :process_outputs]],
        optimization_targets: [
          %{
            type: :inline_function,
            target: :prepare_inputs,
            reason: "Frequently called with similar arguments"
          }
        ]
      }
      
      # Compile with the analysis
      result = TraceStrategy.compile(op, inputs, analysis)
      
      # Should return an optimized operator (or at least a valid one)
      # The EmberEx.Operators.Operator protocol can be implemented by various structs
      assert is_map(result), "Expected result to be a map, got: #{inspect(result)}"
      
      # Verify that the returned value is a callable operator
      output = Operator.call(result, inputs)
      assert is_map(output), "Expected output to be a map, got: #{inspect(output)}"
      
      # The optimized operator should produce the same result
      assert Operator.call(result, inputs) == Operator.call(op, inputs)
    end
  end
  
  # Helper functions for testing
  
  defp create_test_operator do
    SequenceOperator.new([
      MapOperator.new(fn x -> %{value: x.value * 2} end),
      MapOperator.new(fn x -> %{value: x.value + 10} end),
      MapOperator.new(fn x -> 
        # Add a delay to simulate computation time
        Process.sleep(1)
        %{value: x.value, result: "Computed #{x.value}"}
      end)
    ])
  end
end
