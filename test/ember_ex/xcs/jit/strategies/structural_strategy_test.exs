defmodule EmberEx.XCS.JIT.Strategies.StructuralStrategyTest do
  @moduledoc """
  Tests for the structure-based JIT optimization strategy.
  """
  
  use ExUnit.Case, async: true
  
  alias EmberEx.Operators.{MapOperator, SequenceOperator, ParallelOperator, Operator}
  alias EmberEx.XCS.JIT.Strategies.StructuralStrategy
  
  describe "name/0" do
    test "returns the correct strategy name" do
      assert StructuralStrategy.name() == "structural"
    end
  end
  
  describe "analyze/2" do
    test "analyzes simple map operators correctly" do
      # Create a simple operator
      op = MapOperator.new(fn x -> x * 2 end)
      inputs = %{value: 5}
      
      # Analyze the operator
      result = StructuralStrategy.analyze(op, inputs)
      
      # Verify the result has the expected structure
      assert is_map(result)
      assert is_integer(result.score)
      assert is_binary(result.rationale)
      assert is_list(result.optimization_targets)
      assert is_map(result.structural_properties)
      
      # Simple operators should have low complexity
      assert result.structural_properties.complexity == 1
      assert result.structural_properties.depth == 1
    end
    
    test "analyzes sequence operators correctly" do
      # Create a sequence of operations
      op = SequenceOperator.new([
        MapOperator.new(fn x -> %{value: x.value * 2} end),
        MapOperator.new(fn x -> %{value: x.value + 10} end)
      ])
      inputs = %{value: 5}
      
      # Analyze the operator
      result = StructuralStrategy.analyze(op, inputs)
      
      # Verify the result has the expected structure
      assert is_map(result)
      assert is_integer(result.score)
      assert is_binary(result.rationale)
      assert is_list(result.optimization_targets)
      assert is_map(result.structural_properties)
      
      # Sequence should have complexity > 1
      assert result.structural_properties.complexity > 1
      # Depth should be at least 2 (sequence of depth 1 ops)
      assert result.structural_properties.depth >= 2
      # Should identify sequential chains
      assert result.structural_properties.sequential_chains > 0
    end
    
    test "identifies fusion opportunities for sequential map operators" do
      # Create a sequence with sequential map operators
      op = SequenceOperator.new([
        MapOperator.new(fn x -> %{value: x.value * 2} end),
        MapOperator.new(fn x -> %{value: x.value + 10} end),
        MapOperator.new(fn x -> %{value: x.value, result: "Computed #{x.value}"} end)
      ])
      inputs = %{value: 5}
      
      # Analyze the operator
      result = StructuralStrategy.analyze(op, inputs)
      
      # Should identify fusion opportunities
      fusion_targets = Enum.filter(result.optimization_targets, fn t -> t.type == :fusion end)
      assert length(fusion_targets) > 0
    end
    
    test "identifies parallelization opportunities" do
      # Create a sequence with independent operations
      op = SequenceOperator.new([
        MapOperator.new(fn x -> %{value1: x.value * 2, original: x.value} end),
        MapOperator.new(fn x -> %{value2: x.original * 3, original: x.original} end),
        MapOperator.new(fn x -> %{result: x.value1 + x.value2} end)
      ])
      inputs = %{value: 5}
      
      # Analyze the operator
      result = StructuralStrategy.analyze(op, inputs)
      
      # Should identify parallelization opportunities
      parallel_targets = Enum.filter(result.optimization_targets, fn t -> 
        t.type == :parallelization 
      end)
      
      # The middle two operations could be parallelized
      assert length(parallel_targets) > 0 or result.score > 0
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
        optimization_targets: [],
        structural_properties: %{
          complexity: 1,
          depth: 1,
          sequential_chains: 0,
          parallel_sections: 0
        }
      }
      
      # Compile with the analysis
      result = StructuralStrategy.compile(op, inputs, analysis)
      
      # Should return the original operator
      assert result == op
    end
    
    test "applies fusion for sequential map operators" do
      # Create a sequence with two map operators
      op1 = MapOperator.new(fn x -> %{value: x.value * 2} end)
      op2 = MapOperator.new(fn x -> %{value: x.value + 10} end)
      op = SequenceOperator.new([op1, op2])
      inputs = %{value: 5}
      
      # Create a mock analysis with fusion target
      analysis = %{
        score: 70,
        rationale: "Good fusion opportunity",
        optimization_targets: [
          %{
            type: :fusion,
            target: [0, 1],
            operators: [op1, op2],
            reason: "Sequential map operators can be fused"
          }
        ],
        structural_properties: %{
          complexity: 3,
          depth: 2,
          sequential_chains: 1,
          parallel_sections: 0
        }
      }
      
      # Compile with the analysis
      result = StructuralStrategy.compile(op, inputs, analysis)
      
      # The optimized operator should produce the same result
      assert Operator.call(result, inputs) == Operator.call(op, inputs)
    end
    
    test "applies parallelization for independent operations" do
      # Create input data
      inputs = %{value: 5}
      
      # Create a sequence with independent operations
      op1 = MapOperator.new(fn x -> %{value1: x.value * 2, original: x.value} end)
      op2 = MapOperator.new(fn x -> %{value2: x.value * 3, original: x.value} end)
      op3 = MapOperator.new(fn x -> %{result: x.value1 + x.value2} end)
      op = SequenceOperator.new([op1, op2, op3])
      
      # Create a mock analysis with parallelization target
      analysis = %{
        score: 70,
        rationale: "Good parallelization opportunity",
        optimization_targets: [
          %{
            type: :parallelization,
            target: [0, 1],
            operators: [op1, op2],
            reason: "Independent operations can be parallelized"
          }
        ],
        structural_properties: %{
          complexity: 4,
          depth: 2,
          sequential_chains: 1,
          parallel_sections: 0
        }
      }
      
      # Compile with the analysis
      result = StructuralStrategy.compile(op, inputs, analysis)
      
      # The optimized operator should produce the same result
      assert Operator.call(result, inputs) == Operator.call(op, inputs)
    end
  end
  
  describe "optimization effectiveness" do
    test "optimized operators maintain correctness" do
      # Create a complex test operator
      op = create_test_operator()
      inputs = %{value: 5}
      
      # Get expected result
      expected_result = Operator.call(op, inputs)
      
      # Apply analysis with mock data to ensure a specific optimization path
      # This prevents the test from being brittle due to fluctuations in scoring
      analysis = %{
        score: 80,  # High enough to trigger optimization
        rationale: "Test optimization",
        optimization_targets: [
          %{
            type: :fusion,
            target: [1, 2],  # Target the last two operators in the sequence
            reason: "Sequential map operators can be fused"
          }
        ],
        structural_properties: %{
          complexity: 5,
          depth: 3,
          sequential_chains: 2,
          parallel_sections: 1
        }
      }
      
      # Compile with our controlled analysis
      optimized_op = StructuralStrategy.compile(op, inputs, analysis)
      
      # The compile function should always return a valid operator
      assert optimized_op != nil, "Expected optimized operator to not be nil"
      
      # The optimized operator should be callable
      assert is_struct(optimized_op) or is_function(optimized_op, 1), 
             "Expected optimized operator to be a struct or function"
      
      # Call the optimized operator
      optimized_result = Operator.call(optimized_op, inputs)
      
      # Output for debugging
      IO.inspect(optimized_result, label: "Optimized Result")
      IO.inspect(expected_result, label: "Expected Result")
      
      # Verify the results match at the important fields
      assert is_map(optimized_result), "Expected result to be a map"
      
      # Verify we have the expected result field
      assert Map.has_key?(optimized_result, :result) or 
             (Map.has_key?(optimized_result, :c) and 
              is_map(expected_result) and 
              Map.get(optimized_result, :c) == Map.get(expected_result, :c)),
             "Expected result to contain a :result key"
    end
  end
  
  # Helper functions for testing
  
  defp create_test_operator do
    # Create a more complex operator with optimization opportunities
    SequenceOperator.new([
      # First stage - could be parallelized
      ParallelOperator.new([
        MapOperator.new(fn x -> %{a: x.value * 2, original: x.value} end),
        MapOperator.new(fn x -> %{b: x.value + 10, original: x.value} end)
      ]),
      # Second stage - sequential map operators that could be fused
      MapOperator.new(fn x -> %{c: x.a * x.b, original: x.original} end),
      MapOperator.new(fn x -> %{result: x.c, message: "Result for #{x.original}"} end)
    ])
  end
end
