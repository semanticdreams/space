# Training format for reasoning models using the reinforcement method

Per-line training example for reinforcement fine-tuning. Note that `messages` and `tools` are the only reserved keywords. Any other arbitrary key-value data can be included on training datapoints and will be available to reference during grading under the `{{ item.XXX }}` template variable.

## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `messages` | array of oneOf: object (3 properties) | object (3 properties) | object (8 properties) | object (3 properties) | Yes |  |  |  |
| `tools` | array of object (2 properties) | No |  |  | A list of tools the model may generate JSON inputs for. |


### Items in `tools` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes |  | `function` | The type of the tool. Currently, only `function` is supported. |
| `function` | object (4 properties) | Yes |  |  |  |
|   ↳ `parameters` | object (map of object) | No |  |  | The parameters the functions accepts, described as a JSON Schema object. See the [guide](/docs/guides/function-calling) for examples, and the [JSON Schema reference](https://json-schema.org/understanding-json-schema/) for documentation about the format.  <br>  <br> Omitting `parameters` defines a function with an empty parameter list. |
|   ↳   ↳ (additional properties) | object | - | - | - | Additional properties of this object |
|   ↳ `strict` | boolean | No | `false` |  | Whether to enable strict schema adherence when generating the function call. If set to true, the model will follow the exact schema defined in the `parameters` field. Only a subset of JSON Schema is supported when `strict` is `true`. Learn more about Structured Outputs in the [function calling guide](docs/guides/function-calling). |

## Property Details

### `messages` (required)

**Type**: array of oneOf: object (3 properties) | object (3 properties) | object (8 properties) | object (3 properties)

### `tools`

A list of tools the model may generate JSON inputs for.

**Type**: array of object (2 properties)

## Example

```json
{
  "messages": [
    {
      "role": "user",
      "content": "Your task is to take a chemical in SMILES format and predict the number of hydrobond bond donors and acceptors according to Lipinkski's rule. CCN(CC)CCC(=O)c1sc(N)nc1C"
    },
  ],
  # Any other JSON data can be inserted into an example and referenced during RFT grading
  "reference_answer": {
    "donor_bond_counts": 5,
    "acceptor_bond_counts": 7
  }
}

```

