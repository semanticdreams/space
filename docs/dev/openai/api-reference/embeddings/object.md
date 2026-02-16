# The embedding object

Represents an embedding vector returned by embedding endpoint.


## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `index` | integer | Yes |  |  | The index of the embedding in the list of embeddings. |
| `embedding` | array of number | Yes |  |  | The embedding vector, which is a list of floats. The length of vector depends on the model as listed in the [embedding guide](/docs/guides/embeddings). <br>  |
| `object` | string | Yes |  | `embedding` | The object type, which is always "embedding". |

## Property Details

### `index` (required)

The index of the embedding in the list of embeddings.

**Type**: integer

### `embedding` (required)

The embedding vector, which is a list of floats. The length of vector depends on the model as listed in the [embedding guide](/docs/guides/embeddings).


**Type**: array of number

### `object` (required)

The object type, which is always "embedding".

**Type**: string

**Allowed values**: `embedding`

## Example

```json
{
  "object": "embedding",
  "embedding": [
    0.0023064255,
    -0.009327292,
    .... (1536 floats total for ada-002)
    -0.0028842222,
  ],
  "index": 0
}

```

