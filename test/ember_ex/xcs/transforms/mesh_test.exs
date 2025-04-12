defmodule EmberEx.XCS.Transforms.MeshTest do
  @moduledoc """
  Tests for the device mesh-based sharding transform.
  """
  
  use ExUnit.Case, async: true
  
  alias EmberEx.XCS.Transforms.Mesh
  alias EmberEx.Operators.{MapOperator, SequenceOperator, Operator}
  
  describe "new/1" do
    test "creates a new mesh transform with default options" do
      transform = Mesh.new()
      
      assert is_struct(transform, Mesh)
      assert transform.strategy == :data
      assert transform.devices == 1
      assert is_map(transform.config)
    end
    
    test "creates a new mesh transform with custom options" do
      transform = Mesh.new(
        strategy: :model,
        devices: 4,
        config: %{batch_size: 16}
      )
      
      assert transform.strategy == :model
      assert transform.devices == 4
      assert transform.config.batch_size == 16
    end
    
    test "validates strategy" do
      assert_raise ArgumentError, fn ->
        Mesh.new(strategy: :invalid_strategy)
      end
    end
    
    test "validates device count" do
      assert_raise ArgumentError, fn ->
        Mesh.new(devices: 0)
      end
      
      assert_raise ArgumentError, fn ->
        Mesh.new(devices: -1)
      end
    end
  end
  
  describe "apply/2" do
    test "applies data parallelism to a map operator" do
      # Create a simple map operator
      op = MapOperator.new(fn x -> %{value: x.value * 2} end)
      
      # Create a mesh transform with data parallelism
      transform = Mesh.new(strategy: :data, devices: 2)
      
      # Apply the transform
      result = Mesh.apply(transform, op)
      
      # The result should be a valid operator
      assert is_struct(result, Operator) or is_function(result, 1)
      
      # Test with sample input
      input = %{value: 5}
      output = Operator.call(result, input)
      
      # Should produce the same result as the original
      assert output == Operator.call(op, input)
    end
    
    test "applies model parallelism to a sequence operator" do
      # Create a sequence of operations
      op = SequenceOperator.new([
        MapOperator.new(fn x -> %{value: x.value * 2} end),
        MapOperator.new(fn x -> %{value: x.value + 10} end),
        MapOperator.new(fn x -> %{value: x.value, result: "Computed #{x.value}"} end)
      ])
      
      # Create a mesh transform with model parallelism
      transform = Mesh.new(strategy: :model, devices: 3)
      
      # Apply the transform
      result = Mesh.apply(transform, op)
      
      # The result should be a valid operator
      assert is_struct(result, Operator) or is_function(result, 1)
      
      # Test with sample input
      input = %{value: 5}
      output = Operator.call(result, input)
      
      # Should produce the same result as the original
      assert output == Operator.call(op, input)
    end
    
    test "applies pipeline parallelism to a sequence operator" do
      # Create a sequence of operations
      op = SequenceOperator.new([
        MapOperator.new(fn x -> %{value: x.value * 2} end),
        MapOperator.new(fn x -> %{value: x.value + 10} end),
        MapOperator.new(fn x -> %{value: x.value, result: "Computed #{x.value}"} end)
      ])
      
      # Create a mesh transform with pipeline parallelism
      transform = Mesh.new(strategy: :pipeline, devices: 3)
      
      # Apply the transform
      result = Mesh.apply(transform, op)
      
      # The result should be a valid operator
      assert is_struct(result, Operator) or is_function(result, 1)
      
      # Test with sample input
      input = %{value: 5}
      output = Operator.call(result, input)
      
      # Should produce the same result as the original
      assert output == Operator.call(op, input)
    end
  end
  
  describe "partition_data/2" do
    test "partitions data into even chunks" do
      # Create sample data
      data = [1, 2, 3, 4, 5, 6]
      
      # Partition into 2 devices
      transform = Mesh.new(devices: 2)
      {partitions, metadata} = Mesh.partition_data(transform, data)
      
      # Should have 2 partitions
      assert length(partitions) == 2
      assert length(hd(partitions)) == 3
      assert length(Enum.at(partitions, 1)) == 3
      
      # Should include metadata
      assert is_map(metadata)
      assert metadata.original_size == 6
      assert metadata.strategy == :data
    end
    
    test "handles uneven partitioning" do
      # Create sample data
      data = [1, 2, 3, 4, 5]
      
      # Partition into 3 devices
      transform = Mesh.new(devices: 3)
      {partitions, _} = Mesh.partition_data(transform, data)
      
      # Should have 3 partitions
      assert length(partitions) == 3
      
      # Check partition sizes
      partition_sizes = Enum.map(partitions, &length/1)
      assert Enum.sum(partition_sizes) == 5
      
      # Partitions should be as even as possible
      assert Enum.min(partition_sizes) >= 1
      assert Enum.max(partition_sizes) <= 2
    end
  end
  
  describe "combine_results/2" do
    test "combines results from data parallelism" do
      # Create a transform with data parallelism
      transform = Mesh.new(strategy: :data)
      
      # Mock results from multiple devices
      results = [%{value: 1}, %{value: 2}, %{value: 3}]
      metadata = %{strategy: :data, original_size: 3}
      
      # Combine the results
      combined = Mesh.combine_results(transform, {results, metadata})
      
      # For data parallelism, should concatenate results
      assert length(combined) == 3
      assert Enum.at(combined, 0) == %{value: 1}
      assert Enum.at(combined, 1) == %{value: 2}
      assert Enum.at(combined, 2) == %{value: 3}
    end
    
    test "combines results from model parallelism" do
      # Create a transform with model parallelism
      transform = Mesh.new(strategy: :model)
      
      # Mock results from multiple devices, each processing a part of the model
      results = [
        %{value: 10}, # First part result
        %{intermediate: 20}, # Second part result
        %{result: "final"} # Final part result
      ]
      metadata = %{strategy: :model, original_size: 1}
      
      # Combine the results
      combined = Mesh.combine_results(transform, {results, metadata})
      
      # For model parallelism, should merge the maps
      assert is_map(combined)
      assert Map.get(combined, :value) == 10
      assert Map.get(combined, :intermediate) == 20
      assert Map.get(combined, :result) == "final"
    end
  end
  
  describe "integration" do
    test "full data parallelism pipeline" do
      # Create an operator
      op = MapOperator.new(fn x -> 
        # Simulate some computation
        Process.sleep(1)
        %{value: x.value * 2}
      end)
      
      # Create input data
      inputs = [%{value: 1}, %{value: 2}, %{value: 3}, %{value: 4}]
      
      # Create a mesh transform
      transform = Mesh.new(strategy: :data, devices: 2)
      
      # Partition the data
      {partitioned_data, metadata} = Mesh.partition_data(transform, inputs)
      
      # Apply the operator to each partition
      results = Enum.map(partitioned_data, fn partition ->
        Enum.map(partition, fn input ->
          Operator.call(op, input)
        end)
      end)
      
      # Combine the results
      combined = Mesh.combine_results(transform, {results, metadata})
      
      # Verify the results
      expected = Enum.map(inputs, fn input -> 
        %{value: input.value * 2} 
      end)
      
      assert combined == expected
    end
  end
end
