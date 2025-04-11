defmodule EmberEx.Context.ExecutionContextTest do
  @moduledoc """
  Tests for the ExecutionContext module.
  """
  
  use ExUnit.Case, async: true
  
  alias EmberEx.Context.ExecutionContext
  
  # TypeCheck is not available in this project
  
  describe "new/3" do
    test "creates a new execution context with default values" do
      context = ExecutionContext.new()
      
      assert context.config == %{}
      assert context.metadata == %{}
      assert context.state == %{}
      assert context.parent_id == nil
      assert %DateTime{} = context.created_at
      assert String.starts_with?(context.id, "ctx_")
    end
    
    test "creates a new execution context with provided values" do
      config = %{model: "openai/gpt-4"}
      metadata = %{user_id: "123"}
      parent_id = "parent_ctx_123"
      
      context = ExecutionContext.new(config, metadata, parent_id)
      
      assert context.config == config
      assert context.metadata == metadata
      assert context.state == %{}
      assert context.parent_id == parent_id
    end
  end
  
  describe "create_child/3" do
    test "creates a child context with parent id" do
      parent = ExecutionContext.new(%{model: "openai/gpt-4"}, %{user_id: "123"})
      child = ExecutionContext.create_child(parent)
      
      assert child.parent_id == parent.id
      assert child.config == parent.config
      assert child.metadata == parent.metadata
    end
    
    test "creates a child context with config and metadata overrides" do
      parent = ExecutionContext.new(%{model: "openai/gpt-4", temperature: 0.5}, %{user_id: "123"})
      config_override = %{temperature: 0.7}
      metadata_override = %{trace_id: "456"}
      
      child = ExecutionContext.create_child(parent, config_override, metadata_override)
      
      assert child.parent_id == parent.id
      assert child.config == %{model: "openai/gpt-4", temperature: 0.7}
      assert child.metadata == %{user_id: "123", trace_id: "456"}
    end
  end
  
  describe "update_state/3" do
    test "updates a single state value" do
      context = ExecutionContext.new()
      updated = ExecutionContext.update_state(context, :status, :running)
      
      assert updated.state == %{status: :running}
    end
  end
  
  describe "update_state_map/2" do
    test "updates multiple state values" do
      context = ExecutionContext.new()
      updates = %{status: :running, step: 1}
      updated = ExecutionContext.update_state_map(context, updates)
      
      assert updated.state == %{status: :running, step: 1}
    end
    
    test "merges with existing state values" do
      context = ExecutionContext.new()
      |> ExecutionContext.update_state(:status, :pending)
      
      updates = %{step: 1}
      updated = ExecutionContext.update_state_map(context, updates)
      
      assert updated.state == %{status: :pending, step: 1}
    end
  end
  
  describe "get_config/3" do
    test "gets a configuration value" do
      context = ExecutionContext.new(%{model: "openai/gpt-4"})
      
      assert ExecutionContext.get_config(context, :model) == "openai/gpt-4"
    end
    
    test "returns default when key not found" do
      context = ExecutionContext.new()
      
      assert ExecutionContext.get_config(context, :model, "default_model") == "default_model"
    end
  end
  
  describe "update_config/3" do
    test "updates a single config value" do
      context = ExecutionContext.new()
      updated = ExecutionContext.update_config(context, :model, "openai/gpt-4")
      
      assert updated.config == %{model: "openai/gpt-4"}
    end
  end
  
  describe "update_config_map/2" do
    test "updates multiple config values" do
      context = ExecutionContext.new()
      updates = %{model: "openai/gpt-4", temperature: 0.7}
      updated = ExecutionContext.update_config_map(context, updates)
      
      assert updated.config == %{model: "openai/gpt-4", temperature: 0.7}
    end
    
    test "merges with existing config values" do
      context = ExecutionContext.new()
      |> ExecutionContext.update_config(:model, "openai/gpt-4")
      
      updates = %{temperature: 0.7}
      updated = ExecutionContext.update_config_map(context, updates)
      
      assert updated.config == %{model: "openai/gpt-4", temperature: 0.7}
    end
  end
end
