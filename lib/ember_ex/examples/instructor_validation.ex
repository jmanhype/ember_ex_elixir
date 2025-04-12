defmodule EmberEx.Examples.InstructorValidation do
  @moduledoc """
  Demonstrates structured output validation using instructor_ex integration.
  
  This example showcases how EmberEx leverages instructor_ex for structured
  output extraction and validation, following the same pattern as Python Ember's
  integration with the instructor library.
  
  The pattern demonstrates:
  1. Creating structured schemas with Ecto
  2. Using instructor_ex to validate LLM outputs against these schemas
  3. Building operators that ensure type-safe results
  """
  
  alias EmberEx.Operators.{
    MapOperator,
    SequenceOperator,
    LLMOperator, 
    VerifierOperator
  }
  
  # Define schemas for structured data extraction
  defmodule ProductReview do
    @moduledoc """
    Schema for product review structured data extraction.
    """
    use Ecto.Schema
    import Ecto.Changeset
    
    @primary_key false
    embedded_schema do
      field :product_name, :string
      field :rating, :integer
      field :pros, {:array, :string}
      field :cons, {:array, :string}
      field :summary, :string
      field :sentiment, :string
    end
    
    def changeset(review, attrs) do
      review
      |> cast(attrs, [:product_name, :rating, :pros, :cons, :summary, :sentiment])
      |> validate_required([:product_name, :rating, :summary, :sentiment])
      |> validate_inclusion(:rating, 1..5)
      |> validate_inclusion(:sentiment, ["positive", "neutral", "negative"])
    end
  end
  
  defmodule ReviewAnalysis do
    @moduledoc """
    Schema for review analysis results.
    """
    use Ecto.Schema
    import Ecto.Changeset
    
    @primary_key false
    embedded_schema do
      embeds_one :review, ProductReview
      field :key_points, {:array, :string}
      field :improvement_suggestions, {:array, :string}
      field :audience, :string
    end
    
    def changeset(analysis, attrs) do
      analysis
      |> cast(attrs, [:key_points, :improvement_suggestions, :audience])
      |> cast_embed(:review)
      |> validate_required([:review, :key_points])
    end
  end
  
  @doc """
  Creates a review analysis pipeline using instructor_ex integration.
  
  ## Parameters
  
  - model: The LLM model callable to use
  
  ## Returns
  
  An operator pipeline for extracting and analyzing product reviews
  
  ## Examples
  
      iex> model = EmberEx.Models.create_model_callable("openai/gpt-4")
      iex> analyzer = EmberEx.Examples.InstructorValidation.create_review_analyzer(model)
      iex> review_text = "I bought the XYZ Headphones last month. They sound amazing and the battery lasts for days. However, they're a bit tight on my head after a few hours. Overall 4/5 stars."
      iex> EmberEx.Operators.Operator.call(analyzer, review_text)
      %{
      ...>   review: %{
      ...>     product_name: "XYZ Headphones",
      ...>     rating: 4,
      ...>     pros: ["Amazing sound quality", "Long battery life"],
      ...>     cons: ["Tight fit causing discomfort after extended use"],
      ...>     summary: "High-quality headphones with excellent sound and battery life but comfort issues",
      ...>     sentiment: "positive"
      ...>   },
      ...>   key_points: ["Premium audio quality", "Extended battery performance", "Comfort issues during long sessions"],
      ...>   improvement_suggestions: ["Improve headband design for better comfort"],
      ...>   audience: "Audio enthusiasts who prioritize sound quality over extended comfort"
      ...> }
  """
  @spec create_review_analyzer(EmberEx.Models.ModelCallable.t()) :: EmberEx.Operators.Operator.t()
  def create_review_analyzer(model) do
    # 1. Create a structured extraction operator using instructor_ex
    extraction_op = LLMOperator.new(fn input ->
      case model.(%{
        messages: [
          %{
            role: "user", 
            content: """
            Extract structured information from this product review:
            
            #{input}
            """
          }
        ],
        response_model: ProductReview,
        temperature: 0.1
      }) do
        {:ok, review} -> %{review: review}
        {:error, reason} -> %{error: "Extraction failed: #{inspect(reason)}"}
      end
    end, "review_extraction")
    
    # 2. Create a verification operator to ensure extraction succeeded
    verification_op = VerifierOperator.new([
      VerifierOperator.condition(
        fn input -> not Map.has_key?(input, :error) end,
        "Extraction failed"
      )
    ], nil, :extraction_valid)
    
    # 3. Create an analysis operator using the extracted review
    analysis_op = LLMOperator.new(fn %{review: review} = input ->
      case model.(%{
        messages: [
          %{
            role: "user", 
            content: """
            Analyze this product review and provide key points, suggestions for improvement, 
            and the target audience:
            
            Product: #{review.product_name}
            Rating: #{review.rating}/5
            Pros: #{Enum.join(review.pros || [], ", ")}
            Cons: #{Enum.join(review.cons || [], ", ")}
            Summary: #{review.summary}
            """
          }
        ],
        response_model: %{
          key_points: ["string"],
          improvement_suggestions: ["string"],
          audience: "string"
        },
        temperature: 0.2
      }) do
        {:ok, analysis} -> Map.merge(input, analysis)
        {:error, reason} -> Map.put(input, :analysis_error, "Analysis failed: #{inspect(reason)}")
      end
    end, "review_analysis")
    
    # 4. Create a final validation operator to ensure both extraction and analysis succeeded
    final_validation_op = VerifierOperator.new([
      VerifierOperator.condition(
        fn input -> 
          Map.has_key?(input, :review) and 
          Map.has_key?(input, :key_points) and 
          not Map.has_key?(input, :analysis_error)
        end,
        "Analysis pipeline failed"
      )
    ], nil, :analysis_valid)
    
    # 5. Combine all operators into a sequence
    SequenceOperator.new([
      extraction_op,
      verification_op,
      analysis_op,
      final_validation_op,
      # Add a cleanup operator to remove validation fields
      MapOperator.new(fn input -> 
        input 
        |> Map.drop([:extraction_valid, :analysis_valid])
      end, "cleanup")
    ], "review_analysis_pipeline")
  end
  
  @doc """
  Creates an example review analyzer with a mock model.
  
  ## Returns
  
  A review analyzer operator with a mock model
  
  ## Examples
  
      iex> analyzer = EmberEx.Examples.InstructorValidation.create_example()
      iex> review = "The SmartWatch X is great. Battery lasts 3 days and tracking is accurate. The app is a bit clunky though. 4/5."
      iex> EmberEx.Operators.Operator.call(analyzer, review)
      %{
      ...>   review: %{...},
      ...>   key_points: [...],
      ...>   improvement_suggestions: [...],
      ...>   audience: "..."
      ...> }
  """
  @spec create_example() :: EmberEx.Operators.Operator.t()
  def create_example do
    # Create a mock model that simulates instructor_ex integration
    mock_model = fn input ->
      # Extract the review text from the prompt
      review_text = case input do
        %{messages: [%{content: content}]} -> 
          Regex.run(~r/Extract structured information from this product review:\s+(.*)/s, content)
          |> case do
            [_, review] -> review
            _ -> ""
          end
        _ -> ""
      end
      
      # Check if this is the extraction or analysis request
      is_extraction = Map.has_key?(input, :response_model) && 
                     input.response_model == ProductReview
      
      if is_extraction do
        # Mock extraction of product review
        product_name = cond do
          String.contains?(review_text, "SmartWatch") -> "SmartWatch X"
          String.contains?(review_text, "Headphones") -> "XYZ Headphones"
          String.contains?(review_text, "Laptop") -> "UltraBook Pro"
          true -> "Generic Product"
        end
        
        rating = cond do
          review_text =~ "5/5" -> 5
          review_text =~ "4/5" -> 4
          review_text =~ "3/5" -> 3
          review_text =~ "2/5" -> 2
          review_text =~ "1/5" -> 1
          true -> 4  # Default rating
        end
        
        # Extract pros from positive words
        pros = cond do
          review_text =~ "battery" -> ["Long battery life"]
          review_text =~ "sound" -> ["Great sound quality"]
          review_text =~ "fast" -> ["Fast performance"]
          true -> ["Good quality"]
        end
        
        # Extract cons from negative words
        cons = cond do
          review_text =~ "clunky" -> ["Clunky interface"]
          review_text =~ "tight" -> ["Uncomfortable fit"]
          review_text =~ "slow" -> ["Slow performance"]
          true -> ["Minor issues"]
        end
        
        # Determine sentiment based on rating
        sentiment = cond do
          rating >= 4 -> "positive"
          rating == 3 -> "neutral"
          true -> "negative"
        end
        
        # Create the structured product review
        {:ok, %{
          product_name: product_name,
          rating: rating,
          pros: pros,
          cons: cons,
          summary: "#{if rating >= 4, do: "Good", else: "Average"} #{product_name} with #{Enum.at(pros, 0) |> String.downcase()} but #{Enum.at(cons, 0) |> String.downcase()}",
          sentiment: sentiment
        }}
      else
        # Extract product details from analysis request
        product_details = case input do
          %{messages: [%{content: content}]} -> 
            %{
              product: Regex.run(~r/Product: (.*)\n/, content) |> Enum.at(1, "Unknown"),
              rating: Regex.run(~r/Rating: (\d)\/5/, content) |> Enum.at(1, "3") |> String.to_integer(),
              pros: Regex.run(~r/Pros: (.*)\n/, content) |> Enum.at(1, ""),
              cons: Regex.run(~r/Cons: (.*)\n/, content) |> Enum.at(1, "")
            }
          _ -> %{product: "Unknown", rating: 3, pros: "", cons: ""}
        end
        
        # Mock analysis based on product details
        key_points = [
          "#{if product_details.rating >= 4, do: "High", else: "Average"} customer satisfaction",
          "#{String.capitalize(product_details.pros)}"
        ]
        
        # Create improvement suggestions based on cons
        improvement_suggestions = [
          "Improve #{String.downcase(product_details.cons)}"
        ]
        
        # Determine target audience
        audience = cond do
          product_details.product =~ "SmartWatch" -> "Active individuals interested in fitness tracking"
          product_details.product =~ "Headphones" -> "Music enthusiasts who value sound quality"
          product_details.product =~ "Laptop" -> "Professionals seeking balanced performance and portability"
          true -> "General consumers"
        end
        
        {:ok, %{
          key_points: key_points,
          improvement_suggestions: improvement_suggestions,
          audience: audience
        }}
      end
    end
    
    # Create the review analyzer with our mock model
    create_review_analyzer(mock_model)
  end
end
