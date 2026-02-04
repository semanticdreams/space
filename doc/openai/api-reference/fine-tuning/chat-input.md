# Training format for chat models using the supervised method

The per-line training example of a fine-tuning input file for chat models using the supervised method.

## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `messages` | array of oneOf: object (3 properties) | object (3 properties) | object (8 properties) | object (3 properties) | object (3 properties) | No |  |  |  |
| `tools` | array of object (2 properties) | No |  |  | A list of tools the model may generate JSON inputs for. |
| `parallel_tool_calls` | boolean | No | `true` |  | Whether to enable [parallel function calling](/docs/guides/function-calling#configuring-parallel-function-calling) during tool use. |
| `functions` | array of object (3 properties) | No |  |  | A list of functions the model may generate JSON inputs for. |


### Items in `tools` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `function` | The type of the tool. Currently, only `function` is supported. |
| `function` | object (4 properties) | Yes |  |  |  |
|   ↳ `parameters` | object (map of object) | No |  |  | The parameters the functions accepts, described as a JSON Schema object. See the [guide](/docs/guides/function-calling) for examples, and the [JSON Schema reference](https://json-schema.org/understanding-json-schema/) for documentation about the format.  <br>  <br> Omitting `parameters` defines a function with an empty parameter list. |
|   ↳   ↳ (additional properties) | object | - | - | - | Additional properties of this object |
|   ↳ `strict` | boolean | No | `false` |  | Whether to enable strict schema adherence when generating the function call. If set to true, the model will follow the exact schema defined in the `parameters` field. Only a subset of JSON Schema is supported when `strict` is `true`. Learn more about Structured Outputs in the [function calling guide](docs/guides/function-calling). |


### Items in `functions` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `description` | string | No |  |  | A description of what the function does, used by the model to choose when and how to call the function. |
| `name` | string | Yes |  |  | The name of the function to be called. Must be a-z, A-Z, 0-9, or contain underscores and dashes, with a maximum length of 64. |
| `parameters` | object (map of object) | No |  |  | The parameters the functions accepts, described as a JSON Schema object. See the [guide](/docs/guides/function-calling) for examples, and the [JSON Schema reference](https://json-schema.org/understanding-json-schema/) for documentation about the format.  <br>  <br> Omitting `parameters` defines a function with an empty parameter list. |
|   ↳ (additional properties) | object | - | - | - | Additional properties of this object |

## Property Details

### `messages`

**Type**: array of oneOf: object (3 properties) | object (3 properties) | object (8 properties) | object (3 properties) | object (3 properties)

### `tools`

A list of tools the model may generate JSON inputs for.

**Type**: array of object (2 properties)

### `parallel_tool_calls`

Whether to enable [parallel function calling](/docs/guides/function-calling#configuring-parallel-function-calling) during tool use.

**Type**: boolean

### `functions`

A list of functions the model may generate JSON inputs for.

**Type**: array of object (3 properties)

## Example

```json
{
  "messages": [
    { "role": "user", "content": "What is the weather in San Francisco?" },
    {
      "role": "assistant",
      "tool_calls": [
        {
          "id": "call_id",
          "type": "function",
          "function": {
            "name": "get_current_weather",
            "arguments": "{\"location\": \"San Francisco, USA\", \"format\": \"celsius\"}"
          }
        }
      ]
    }
  ],
  "parallel_tool_calls": false,
  "tools": [
    {
      "type": "function",
      "function": {
        "name": "get_current_weather",
        "description": "Get the current weather",
        "parameters": {
          "type": "object",
          "properties": {
            "location": {
                "type": "string",
                "description": "The city and country, eg. San Francisco, USA"
            },
            "format": { "type": "string", "enum": ["celsius", "fahrenheit"] }
          },
          "required": ["location", "format"]
        }
      }
    }
  ]
}

```

