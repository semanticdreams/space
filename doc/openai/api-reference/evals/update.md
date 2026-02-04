# Update an eval

`POST` `/evals/{eval_id}`

Update certain properties of an evaluation.


## Parameters

### Path Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `eval_id` | string | Yes | The ID of the evaluation to update. |

## Request Body

Request to update an evaluation

### Content Type: `application/json`

**Type**: object (2 properties)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `name` | string | No |  |  | Rename the evaluation. |
| `metadata` | map | No |  |  | Set of 16 key-value pairs that can be attached to an object. This can be <br> useful for storing additional information about the object in a structured <br> format, and querying for objects via API or the dashboard.  <br>  <br> Keys are strings with a maximum length of 64 characters. Values are strings <br> with a maximum length of 512 characters. <br>  |
|   ↳ (additional properties) | string | - | - | - | Additional properties of this object |
## Responses

### 200 - The updated evaluation

#### Content Type: `application/json`

#### Eval

**Type**: object (7 properties)

An Eval object with a data source config and testing criteria.
An Eval represents a task to be done for your LLM integration.
Like:
 - Improve the quality of my chatbot
 - See how well my chatbot handles customer support
 - Check if o3-mini is better at my usecase than gpt-4o


#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `object` | string | Yes | `eval` | `eval` | The object type. |
| `id` | string | Yes |  |  | Unique identifier for the evaluation. |
| `name` | string | Yes |  |  | The name of the evaluation. |
| `data_source_config` | object | Yes |  |  | Configuration of data sources used in runs of the evaluation. |
| `testing_criteria` | array of oneOf: object (6 properties) | object (5 properties) | object (6 properties) | object (5 properties) | object (7 properties) | Yes | `eval` |  | A list of testing criteria. |
| `created_at` | integer | Yes |  |  | The Unix timestamp (in seconds) for when the eval was created. |
| `metadata` | map | Yes |  |  | Set of 16 key-value pairs that can be attached to an object. This can be <br> useful for storing additional information about the object in a structured <br> format, and querying for objects via API or the dashboard.  <br>  <br> Keys are strings with a maximum length of 64 characters. Values are strings <br> with a maximum length of 512 characters. <br>  |
|   ↳ (additional properties) | string | - | - | - | Additional properties of this object |
**Example:**

```json
{
  "object": "eval",
  "id": "eval_67abd54d9b0081909a86353f6fb9317a",
  "data_source_config": {
    "type": "custom",
    "item_schema": {
      "type": "object",
      "properties": {
        "label": {"type": "string"},
      },
      "required": ["label"]
    },
    "include_sample_schema": true
  },
  "testing_criteria": [
    {
      "name": "My string check grader",
      "type": "string_check",
      "input": "{{sample.output_text}}",
      "reference": "{{item.label}}",
      "operation": "eq",
    }
  ],
  "name": "External Data Eval",
  "created_at": 1739314509,
  "metadata": {
    "test": "synthetics",
  }
}

```

## Examples

### Request Examples

#### curl
```bash
curl https://api.openai.com/v1/evals/eval_67abd54d9b0081909a86353f6fb9317a \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"name": "Updated Eval", "metadata": {"description": "Updated description"}}'

```

### Response Example

```json
{
  "object": "eval",
  "id": "eval_67abd54d9b0081909a86353f6fb9317a",
  "data_source_config": {
    "type": "custom",
    "schema": {
      "type": "object",
      "properties": {
        "item": {
          "type": "object",
          "properties": {
            "input": {
              "type": "string"
            },
            "ground_truth": {
              "type": "string"
            }
          },
          "required": [
            "input",
            "ground_truth"
          ]
        }
      },
      "required": [
        "item"
      ]
    }
  },
  "testing_criteria": [
    {
      "name": "String check",
      "id": "String check-2eaf2d8d-d649-4335-8148-9535a7ca73c2",
      "type": "string_check",
      "input": "{{item.input}}",
      "reference": "{{item.ground_truth}}",
      "operation": "eq"
    }
  ],
  "name": "Updated Eval",
  "created_at": 1739314509,
  "metadata": {"description": "Updated description"},
}

```

