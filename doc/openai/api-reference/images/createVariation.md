# Create image variation

`POST` `/images/variations`

Creates a variation of a given image. This endpoint only supports `dall-e-2`.

## Request Body

### Content Type: `multipart/form-data`

**Type**: object (6 properties)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `image` | string | Yes |  |  | The image to use as the basis for the variation(s). Must be a valid PNG file, less than 4MB, and square. |
| `model` | anyOf: string | string | No | `dall-e-2` |  | The model to use for image generation. Only `dall-e-2` is supported at this time. |
| `n` | integer | No | `1` |  | The number of images to generate. Must be between 1 and 10. |
| `response_format` | string | No | `url` | `url`, `b64_json` | The format in which the generated images are returned. Must be one of `url` or `b64_json`. URLs are only valid for 60 minutes after the image has been generated. |
| `size` | string | No | `1024x1024` | `256x256`, `512x512`, `1024x1024` | The size of the generated images. Must be one of `256x256`, `512x512`, or `1024x1024`. |
| `user` | string | No |  |  | A unique identifier representing your end-user, which can help OpenAI to monitor and detect abuse. [Learn more](/docs/guides/safety-best-practices#end-user-ids). <br>  |
## Responses

### 200 - OK

#### Content Type: `application/json`

#### Image generation response

**Type**: object (3 properties)

The response from the image generation endpoint.

#### Properties:

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
**Example:**

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

## Examples

### Request Examples

#### curl
```bash
curl https://api.openai.com/v1/images/variations \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -F image="@otter.png" \
  -F n=2 \
  -F size="1024x1024"

```

#### python
```python
from openai import OpenAI
client = OpenAI()

response = client.images.create_variation(
  image=open("image_edit_original.png", "rb"),
  n=2,
  size="1024x1024"
)

```

#### node.js
```javascript
import fs from "fs";
import OpenAI from "openai";

const openai = new OpenAI();

async function main() {
  const image = await openai.images.createVariation({
    image: fs.createReadStream("otter.png"),
  });

  console.log(image.data);
}
main();
```

#### csharp
```csharp
using System;

using OpenAI.Images;

ImageClient client = new(
    model: "dall-e-2",
    apiKey: Environment.GetEnvironmentVariable("OPENAI_API_KEY")
);

GeneratedImage image = client.GenerateImageVariation(imageFilePath: "otter.png");

Console.WriteLine(image.ImageUri);

```

### Response Example

```json
{
  "created": 1589478378,
  "data": [
    {
      "url": "https://..."
    },
    {
      "url": "https://..."
    }
  ]
}

```

