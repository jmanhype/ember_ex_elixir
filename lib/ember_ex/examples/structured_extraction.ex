defmodule EmberEx.Examples.StructuredExtraction do
  @moduledoc """
  Demonstrates structured data extraction from text using EmberEx.
  
  This example shows how to extract structured information from text documents
  using a combination of operators, including ContainerOperator for modular
  processing pipelines.
  
  The pattern follows these steps:
  1. Document preparation - Clean and prepare the input document
  2. Extraction - Extract structured information using LLMs
  3. Validation - Validate the extracted information
  4. Normalization - Normalize the extracted data to a consistent format
  """
  
  alias EmberEx.Operators.{
    MapOperator,
    SequenceOperator,
    ContainerOperator,
    VerifierOperator
  }
  
  @doc """
  Creates an extraction pipeline for processing resumes.
  
  ## Parameters
  
  - model: Model callable for generating responses
  
  ## Returns
  
  A container operator that extracts structured information from resumes
  
  ## Examples
  
      iex> model = EmberEx.Models.create_model_callable("openai/gpt-4")
      iex> extractor = EmberEx.Examples.StructuredExtraction.create_resume_extractor(model)
      iex> resume_text = "John Doe\\nSoftware Engineer\\n...experience with Python and Elixir..."
      iex> EmberEx.Operators.Operator.call(extractor, resume_text)
      %{
      ...>   contact_info: %{name: "John Doe", email: "john@example.com"},
      ...>   skills: ["Python", "Elixir"],
      ...>   experience: [
      ...>     %{title: "Software Engineer", company: "Tech Corp", years: "2018-2021"}
      ...>   ],
      ...>   confidence: 0.85
      ...> }
  """
  @spec create_resume_extractor(EmberEx.Models.ModelCallable.t()) :: EmberEx.Operators.Operator.t()
  def create_resume_extractor(model) do
    # 1. Document Preparation Operator
    document_prep_op = MapOperator.new(fn text ->
      # Remove excessive whitespace and normalize
      cleaned_text = text
      |> String.trim()
      |> String.replace(~r/\s+/, " ")
      
      %{
        raw_text: text,
        cleaned_text: cleaned_text
      }
    end, "document_preparation")
    
    # 2. Contact Information Extraction Operator
    contact_extraction_op = MapOperator.new(fn input ->
      prompt = """
      Extract the person's contact information from the following resume text.
      Return as JSON with the following schema:
      {
        "name": "Full Name",
        "email": "email address if present",
        "phone": "phone number if present",
        "location": "location if present"
      }
      
      Resume:
      #{input.cleaned_text}
      """
      
      case model.(%{
        messages: [%{role: "user", content: prompt}],
        response_format: %{type: "json_object"}
      }) do
        {:ok, response} ->
          contact_info = case Jason.decode(response.content) do
            {:ok, data} -> data
            _ -> %{}
          end
          
          Map.put(input, :contact_info, contact_info)
          
        {:error, _} ->
          Map.put(input, :contact_info, %{})
      end
    end, "contact_extraction")
    
    # 3. Skills Extraction Operator
    skills_extraction_op = MapOperator.new(fn input ->
      prompt = """
      Extract the technical skills from the following resume text.
      Return as JSON with the following schema:
      {
        "skills": ["skill1", "skill2", "skill3"]
      }
      
      Resume:
      #{input.cleaned_text}
      """
      
      case model.(%{
        messages: [%{role: "user", content: prompt}],
        response_format: %{type: "json_object"}
      }) do
        {:ok, response} ->
          skills = case Jason.decode(response.content) do
            {:ok, %{"skills" => skills}} -> skills
            _ -> []
          end
          
          Map.put(input, :skills, skills)
          
        {:error, _} ->
          Map.put(input, :skills, [])
      end
    end, "skills_extraction")
    
    # 4. Experience Extraction Operator
    experience_extraction_op = MapOperator.new(fn input ->
      prompt = """
      Extract the work experience from the following resume text.
      Return as JSON with the following schema:
      {
        "experience": [
          {
            "title": "job title",
            "company": "company name",
            "years": "duration (e.g., 2018-2021)",
            "description": "brief description if available"
          }
        ]
      }
      
      Resume:
      #{input.cleaned_text}
      """
      
      case model.(%{
        messages: [%{role: "user", content: prompt}],
        response_format: %{type: "json_object"}
      }) do
        {:ok, response} ->
          experience = case Jason.decode(response.content) do
            {:ok, %{"experience" => experience}} -> experience
            _ -> []
          end
          
          Map.put(input, :experience, experience)
          
        {:error, _} ->
          Map.put(input, :experience, [])
      end
    end, "experience_extraction")
    
    # 5. Validation Operator
    validation_op = MapOperator.new(fn input ->
      # Define validation conditions
      name_condition = VerifierOperator.not_empty("Name cannot be empty")
      skills_condition = VerifierOperator.condition(
        fn skills -> is_list(skills) and length(skills) > 0 end,
        "Skills must be a non-empty list"
      )
      
      # Create validators
      name_validator = VerifierOperator.new([name_condition], "name")
      skills_validator = VerifierOperator.new([skills_condition], "skills")
      
      # Run validation
      name_result = EmberEx.Operators.Operator.call(name_validator, input.contact_info["name"])
      skills_result = EmberEx.Operators.Operator.call(skills_validator, input.skills)
      
      # Calculate confidence score based on validation results
      validation_score = [
        if(name_result.passed, do: 1.0, else: 0.0),
        if(skills_result.passed, do: 1.0, else: 0.0),
        if(length(input.experience) > 0, do: 1.0, else: 0.0)
      ]
      |> Enum.sum()
      |> then(&(&1 / 3))
      
      Map.put(input, :confidence, validation_score)
    end, "validation")
    
    # 6. Result Formatter Operator
    formatter_op = MapOperator.new(fn input ->
      %{
        contact_info: input.contact_info,
        skills: input.skills,
        experience: input.experience,
        confidence: input.confidence
      }
    end, "formatter")
    
    # Create extraction components with named operators
    extraction_components = [
      {:contact, contact_extraction_op},
      {:skills, skills_extraction_op}, 
      {:experience, experience_extraction_op}
    ]
    
    # Use the ContainerOperator to create a data extraction pipeline
    ContainerOperator.collecting([
      document_prep_op,
      # The extraction components can run in parallel
      EmberEx.Operators.MapReduceOperator.new(
        &(&1), # identity function as map_fn
        EmberEx.Operators.ParallelOperator.new([
          contact_extraction_op,
          skills_extraction_op,
          experience_extraction_op
        ]),
        &(Enum.reduce(&1, %{}, fn result, acc -> Map.merge(acc, result) end))
      ),
      validation_op,
      formatter_op
    ])
    |> EmberEx.Operators.BaseOperator.set_name("resume_extractor")
  end
  
  @doc """
  Creates a simple example extractor with mocked model for demonstration.
  
  ## Returns
  
  A container operator that extracts information using a mock model
  
  ## Examples
  
      iex> extractor = EmberEx.Examples.StructuredExtraction.create_example()
      iex> resume = "John Doe\\nSenior Developer at XYZ Corp\\nSkills: Elixir, Python, React"
      iex> EmberEx.Operators.Operator.call(extractor, resume)
      %{
      ...>   contact_info: %{"name" => "John Doe", "email" => "john@example.com"},
      ...>   skills: ["Elixir", "Python", "React"],
      ...>   experience: [%{"company" => "XYZ Corp", "title" => "Senior Developer"}],
      ...>   confidence: 1.0
      ...> }
  """
  @spec create_example() :: EmberEx.Operators.Operator.t()
  def create_example do
    # Create a mock model that returns fixed responses based on input analysis
    mock_model = fn %{messages: [%{content: prompt}]} ->
      cond do
        String.contains?(prompt, "contact information") ->
          {:ok, %{content: """
            {
              "name": "John Doe",
              "email": "john@example.com",
              "phone": "555-123-4567",
              "location": "San Francisco, CA"
            }
          """}}
          
        String.contains?(prompt, "technical skills") ->
          # Extract skills from the resume text
          skills = 
            Regex.run(~r/Skills:(.+)/, prompt) 
            |> case do
              [_, skills_text] -> 
                skills_text
                |> String.split(~r/[,;]/)
                |> Enum.map(&String.trim/1)
                |> Enum.reject(&(&1 == ""))
              _ -> ["Elixir", "JavaScript", "Python"] # Default skills if not found
            end
          
          {:ok, %{content: """
            {
              "skills": #{Jason.encode!(skills)}
            }
          """}}
          
        String.contains?(prompt, "work experience") ->
          # Simple regex to extract job titles and companies
          job_info = 
            Regex.run(~r/([A-Za-z ]+) at ([A-Za-z ]+)/, prompt) 
            |> case do
              [_, title, company] -> [%{"title" => title, "company" => company}]
              _ -> [%{"title" => "Software Engineer", "company" => "ABC Inc"}]
            end
          
          {:ok, %{content: """
            {
              "experience": #{Jason.encode!(job_info)}
            }
          """}}
          
        true ->
          {:ok, %{content: "{}"}}
      end
    end
    
    create_resume_extractor(mock_model)
  end
end
