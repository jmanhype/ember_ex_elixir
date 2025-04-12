defmodule EmberEx.Core.Data.DatasetTest do
  @moduledoc """
  Tests for the Dataset module.
  """
  
  use ExUnit.Case, async: true
  
  alias EmberEx.Core.Data.Dataset
  
  describe "new/2" do
    test "creates a new dataset from list" do
      data = [%{id: 1, value: "one"}, %{id: 2, value: "two"}]
      {:ok, dataset} = Dataset.new(data, name: "test_dataset")
      
      assert dataset.name == "test_dataset"
      assert dataset.size == 2
      assert is_map(dataset.metadata)
    end
    
    test "creates a new dataset with schema" do
      data = [%{id: 1, value: "one"}, %{id: 2, value: "two"}]
      schema = %{
        id: {:integer, required: true},
        value: {:string, required: true}
      }
      
      {:ok, dataset} = Dataset.new(data, name: "test_dataset", schema: schema)
      
      assert dataset.schema == schema
      assert dataset.size == 2
    end
    
    test "validates data against schema" do
      data = [%{id: 1, value: "one"}, %{id: "not_an_integer", value: "two"}]
      schema = %{
        id: {:integer, required: true},
        value: {:string, required: true}
      }
      
      {:error, reason} = Dataset.new(data, name: "test_dataset", schema: schema)
      assert is_binary(reason)
      assert String.contains?(reason, "schema validation")
    end
    
    test "handles empty data" do
      {:ok, dataset} = Dataset.new([], name: "empty_dataset")
      
      assert dataset.size == 0
      assert dataset.name == "empty_dataset"
    end
  end
  
  describe "get_batch/2" do
    test "retrieves a batch of data" do
      data = Enum.map(1..10, fn i -> %{id: i, value: "item_#{i}"} end)
      {:ok, dataset} = Dataset.new(data, name: "test_dataset")
      
      {:ok, batch, _context} = Dataset.get_batch(dataset, 3)
      
      assert length(batch) == 3
      assert Enum.all?(batch, fn item -> is_map(item) end)
    end
    
    test "retrieves all data when batch size exceeds dataset size" do
      data = Enum.map(1..5, fn i -> %{id: i, value: "item_#{i}"} end)
      {:ok, dataset} = Dataset.new(data, name: "test_dataset")
      
      {:ok, batch, _context} = Dataset.get_batch(dataset, 10)
      
      assert length(batch) == 5
    end
    
    test "handles empty dataset" do
      {:ok, dataset} = Dataset.new([], name: "empty_dataset")
      
      {:ok, batch, _context} = Dataset.get_batch(dataset, 5)
      
      assert batch == []
    end
    
    test "supports pagination with context" do
      data = Enum.map(1..10, fn i -> %{id: i, value: "item_#{i}"} end)
      {:ok, dataset} = Dataset.new(data, name: "test_dataset")
      
      # Get first batch
      {:ok, batch1, context1} = Dataset.get_batch(dataset, 3)
      assert length(batch1) == 3
      
      # Get second batch
      {:ok, batch2, context2} = Dataset.get_batch(dataset, 3, context1)
      assert length(batch2) == 3
      assert batch1 != batch2
      
      # Get third batch
      {:ok, batch3, context3} = Dataset.get_batch(dataset, 3, context2)
      assert length(batch3) == 3
      
      # Get fourth batch (should have only 1 item left)
      {:ok, batch4, _context4} = Dataset.get_batch(dataset, 3, context3)
      assert length(batch4) == 1
    end
  end
  
  describe "map/2" do
    test "applies a function to all items" do
      data = [%{value: 1}, %{value: 2}, %{value: 3}]
      {:ok, dataset} = Dataset.new(data, name: "test_dataset")
      
      {:ok, mapped_dataset} = Dataset.map(dataset, fn item -> 
        %{value: item.value * 2}
      end)
      
      {:ok, items, _} = Dataset.get_batch(mapped_dataset, 10)
      
      assert items == [%{value: 2}, %{value: 4}, %{value: 6}]
      assert mapped_dataset.name == "test_dataset:mapped"
    end
    
    test "preserves metadata" do
      data = [%{value: 1}, %{value: 2}]
      metadata = %{source: "test", timestamp: DateTime.utc_now()}
      {:ok, dataset} = Dataset.new(data, name: "test_dataset", metadata: metadata)
      
      {:ok, mapped_dataset} = Dataset.map(dataset, fn item -> 
        %{value: item.value * 2}
      end)
      
      assert mapped_dataset.metadata.source == metadata.source
      assert mapped_dataset.metadata.timestamp == metadata.timestamp
      assert mapped_dataset.metadata.parent == "test_dataset"
    end
  end
  
  describe "filter/2" do
    test "filters items based on predicate" do
      data = [%{id: 1, value: 10}, %{id: 2, value: 20}, %{id: 3, value: 30}]
      {:ok, dataset} = Dataset.new(data, name: "test_dataset")
      
      {:ok, filtered_dataset} = Dataset.filter(dataset, fn item -> 
        item.value > 15
      end)
      
      {:ok, items, _} = Dataset.get_batch(filtered_dataset, 10)
      
      assert length(items) == 2
      assert Enum.all?(items, fn item -> item.value > 15 end)
      assert filtered_dataset.name == "test_dataset:filtered"
    end
    
    test "handles empty result" do
      data = [%{id: 1, value: 10}, %{id: 2, value: 20}]
      {:ok, dataset} = Dataset.new(data, name: "test_dataset")
      
      {:ok, filtered_dataset} = Dataset.filter(dataset, fn _ -> false end)
      
      {:ok, items, _} = Dataset.get_batch(filtered_dataset, 10)
      
      assert items == []
      assert filtered_dataset.size == 0
    end
  end
  
  describe "to_list/1" do
    test "converts dataset to list" do
      data = Enum.map(1..5, fn i -> %{id: i, value: "item_#{i}"} end)
      {:ok, dataset} = Dataset.new(data, name: "test_dataset")
      
      {:ok, list} = Dataset.to_list(dataset)
      
      assert list == data
      assert length(list) == 5
    end
    
    test "handles empty dataset" do
      {:ok, dataset} = Dataset.new([], name: "empty_dataset")
      
      {:ok, list} = Dataset.to_list(dataset)
      
      assert list == []
    end
  end
  
  describe "split/3" do
    test "splits dataset by ratio" do
      data = Enum.map(1..100, fn i -> %{id: i, value: "item_#{i}"} end)
      {:ok, dataset} = Dataset.new(data, name: "test_dataset")
      
      {:ok, train_dataset, test_dataset} = Dataset.split(dataset, 0.7)
      
      assert train_dataset.size == 70
      assert test_dataset.size == 30
      assert train_dataset.name == "test_dataset:train"
      assert test_dataset.name == "test_dataset:test"
    end
    
    test "splits dataset with custom names" do
      data = Enum.map(1..10, fn i -> %{id: i, value: "item_#{i}"} end)
      {:ok, dataset} = Dataset.new(data, name: "test_dataset")
      
      {:ok, first, second} = Dataset.split(
        dataset, 
        0.6, 
        first_name: "custom_first", 
        second_name: "custom_second"
      )
      
      assert first.name == "custom_first"
      assert second.name == "custom_second"
    end
    
    test "handles extreme ratios" do
      data = Enum.map(1..10, fn i -> %{id: i, value: "item_#{i}"} end)
      {:ok, dataset} = Dataset.new(data, name: "test_dataset")
      
      # All in first dataset
      {:ok, first, second} = Dataset.split(dataset, 1.0)
      assert first.size == 10
      assert second.size == 0
      
      # All in second dataset
      {:ok, first, second} = Dataset.split(dataset, 0.0)
      assert first.size == 0
      assert second.size == 10
    end
  end
  
  describe "shuffle/1" do
    test "shuffles the dataset items" do
      data = Enum.map(1..100, fn i -> %{id: i, value: "item_#{i}"} end)
      {:ok, dataset} = Dataset.new(data, name: "test_dataset")
      
      {:ok, shuffled_dataset} = Dataset.shuffle(dataset)
      
      {:ok, original_items} = Dataset.to_list(dataset)
      {:ok, shuffled_items} = Dataset.to_list(shuffled_dataset)
      
      # Items should be the same but in different order
      assert Enum.sort_by(original_items, & &1.id) == Enum.sort_by(shuffled_items, & &1.id)
      
      # Very unlikely that the shuffle would result in the same order
      assert original_items != shuffled_items
    end
    
    test "preserves metadata and size" do
      data = Enum.map(1..10, fn i -> %{id: i, value: "item_#{i}"} end)
      {:ok, dataset} = Dataset.new(data, name: "test_dataset", metadata: %{source: "test"})
      
      {:ok, shuffled_dataset} = Dataset.shuffle(dataset)
      
      assert shuffled_dataset.size == dataset.size
      assert shuffled_dataset.metadata.source == "test"
    end
  end
  
  describe "batch/2" do
    test "creates a dataset with batched items" do
      data = Enum.map(1..10, fn i -> %{id: i, value: "item_#{i}"} end)
      {:ok, dataset} = Dataset.new(data, name: "test_dataset")
      
      {:ok, batched_dataset} = Dataset.batch(dataset, 3)
      
      {:ok, batches, _} = Dataset.get_batch(batched_dataset, 10)
      
      assert length(batches) == 4  # 3 batches of 3, plus 1 batch of 1
      assert length(Enum.at(batches, 0)) == 3
      assert length(Enum.at(batches, 1)) == 3
      assert length(Enum.at(batches, 2)) == 3
      assert length(Enum.at(batches, 3)) == 1
    end
    
    test "handles batch size larger than dataset" do
      data = Enum.map(1..5, fn i -> %{id: i, value: "item_#{i}"} end)
      {:ok, dataset} = Dataset.new(data, name: "test_dataset")
      
      {:ok, batched_dataset} = Dataset.batch(dataset, 10)
      
      {:ok, batches, _} = Dataset.get_batch(batched_dataset, 10)
      
      assert length(batches) == 1
      assert length(Enum.at(batches, 0)) == 5
    end
  end
end
