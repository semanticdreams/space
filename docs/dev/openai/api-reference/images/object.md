# The image generation response

The response from the image generation endpoint.

## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `created` | integer | Yes |  |  | The Unix timestamp (in seconds) of when the image was created. |
| `data` | array of object (3 properties) | No |  |  | The list of generated images. |
| `usage` | object (4 properties) | No |  |  | For `gpt-image-1` only, the token usage information for the image generation. <br>  |
|   ↳ `output_tokens` | integer | Yes |  |  | The number of image tokens in the output image. |
|   ↳ `input_tokens_details` | object (2 properties) | Yes |  |  | The input tokens detailed information for the image generation. |


### Items in `data` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `b64_json` | string | No |  |  | The base64-encoded JSON of the generated image. Default value for `gpt-image-1`, and only present if `response_format` is set to `b64_json` for `dall-e-2` and `dall-e-3`. |
| `url` | string | No |  |  | When using `dall-e-2` or `dall-e-3`, the URL of the generated image if `response_format` is set to `url` (default value). Unsupported for `gpt-image-1`. |
| `revised_prompt` | string | No |  |  | For `dall-e-3` only, the revised prompt that was used to generate the image. |

## Property Details

### `created` (required)

The Unix timestamp (in seconds) of when the image was created.

**Type**: integer

### `data`

The list of generated images.

**Type**: array of object (3 properties)

### `usage`

For `gpt-image-1` only, the token usage information for the image generation.


**Type**: object (4 properties)

**Nested Properties**:

* `total_tokens`, `input_tokens`, `output_tokens`, `input_tokens_details`

## Example

```json
{
  "created": 1713833628,
  "data": [
    {
      "b64_json": "..."
    }
  ],
  "usage": {
    "total_tokens": 100,
    "input_tokens": 50,
    "output_tokens": 50,
    "input_tokens_details": {
      "text_tokens": 10,
      "image_tokens": 40
    }
  }
}

```

