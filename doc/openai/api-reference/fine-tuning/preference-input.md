# Training format for chat models using the preference method

The per-line training example of a fine-tuning input file for chat models using the dpo method.

## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `input` | object (3 properties) | No |  |  |  |
|   ↳ `parallel_tool_calls` | boolean | No | `true` |  | Whether to enable [parallel function calling](/docs/guides/function-calling#configuring-parallel-function-calling) during tool use. |


### Items in `tools` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `function` | The type of the tool. Currently, only `function` is supported. |
| `function` | object (4 properties) | Yes |  |  |  |
|   ↳ `parameters` | object (map of object) | No |  |  | The parameters the functions accepts, described as a JSON Schema object. See the [guide](/docs/guides/function-calling) for examples, and the [JSON Schema reference](https://json-schema.org/understanding-json-schema/) for documentation about the format.  <br>  <br> Omitting `parameters` defines a function with an empty parameter list. |
|   ↳   ↳ (additional properties) | object | - | - | - | Additional properties of this object |
|   ↳ `strict` | boolean | No | `false` |  | Whether to enable strict schema adherence when generating the function call. If set to true, the model will follow the exact schema defined in the `parameters` field. Only a subset of JSON Schema is supported when `strict` is `true`. Learn more about Structured Outputs in the [function calling guide](docs/guides/function-calling). |
| `preferred_completion` | array of oneOf: object (7 properties) | No |  |  | The preferred completion message for the output. |
| `non_preferred_completion` | array of oneOf: object (7 properties) | No |  |  | The non-preferred completion message for the output. |

## Property Details

### `input`

**Type**: object (3 properties)

**Nested Properties**:

* `messages`, `tools`, `parallel_tool_calls`

### `preferred_completion`

The preferred completion message for the output.

**Type**: array of oneOf: object (7 properties)

### `non_preferred_completion`

The non-preferred completion message for the output.

**Type**: array of oneOf: object (7 properties)

## Example

```json
{
  "input": {
    "messages": [
      { "role": "user", "content": "What is the weather in San Francisco?" }
    ]
  },
  "preferred_completion": [
    {
      "role": "assistant",
      "content": "The weather in San Francisco is 70 degrees Fahrenheit."
    }
  ],
  "non_preferred_completion": [
    {
      "role": "assistant",
      "content": "The weather in San Francisco is 21 degrees Celsius."
    }
  ]
}

```

