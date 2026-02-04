# Create image edit

`POST` `/images/edits`

Creates an edited or extended image given one or more source images and a prompt. This endpoint only supports `gpt-image-1` and `dall-e-2`.

## Request Body

### Content Type: `multipart/form-data`

**Type**: object (10 properties)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `image` | anyOf: string | array of string | Yes |  |  | The image(s) to edit. Must be a supported image file or an array of images. <br>  <br> For `gpt-image-1`, each image should be a `png`, `webp`, or `jpg` file less  <br> than 25MB. You can provide up to 16 images. <br>  <br> For `dall-e-2`, you can only provide one image, and it should be a square  <br> `png` file less than 4MB. <br>  |
| `prompt` | string | Yes |  |  | A text description of the desired image(s). The maximum length is 1000 characters for `dall-e-2`, and 32000 characters for `gpt-image-1`. |
| `mask` | string | No |  |  | An additional image whose fully transparent areas (e.g. where alpha is zero) indicate where `image` should be edited. If there are multiple images provided, the mask will be applied on the first image. Must be a valid PNG file, less than 4MB, and have the same dimensions as `image`. |
| `background` | string | No | `auto` | `transparent`, `opaque`, `auto` | Allows to set transparency for the background of the generated image(s).  <br> This parameter is only supported for `gpt-image-1`. Must be one of  <br> `transparent`, `opaque` or `auto` (default value). When `auto` is used, the  <br> model will automatically determine the best background for the image. <br>  <br> If `transparent`, the output format needs to support transparency, so it  <br> should be set to either `png` (default value) or `webp`. <br>  |
| `model` | anyOf: string | string | No | `dall-e-2` |  | The model to use for image generation. Only `dall-e-2` and `gpt-image-1` are supported. Defaults to `dall-e-2` unless a parameter specific to `gpt-image-1` is used. |
| `n` | integer | No | `1` |  | The number of images to generate. Must be between 1 and 10. |
| `size` | string | No | `1024x1024` | `256x256`, `512x512`, `1024x1024`, `1536x1024`, `1024x1536`, `auto` | The size of the generated images. Must be one of `1024x1024`, `1536x1024` (landscape), `1024x1536` (portrait), or `auto` (default value) for `gpt-image-1`, and one of `256x256`, `512x512`, or `1024x1024` for `dall-e-2`. |
| `response_format` | string | No | `url` | `url`, `b64_json` | The format in which the generated images are returned. Must be one of `url` or `b64_json`. URLs are only valid for 60 minutes after the image has been generated. This parameter is only supported for `dall-e-2`, as `gpt-image-1` will always return base64-encoded images. |
| `user` | string | No |  |  | A unique identifier representing your end-user, which can help OpenAI to monitor and detect abuse. [Learn more](/docs/guides/safety-best-practices#end-user-ids). <br>  |
| `quality` | string | No | `auto` | `standard`, `low`, `medium`, `high`, `auto` | The quality of the image that will be generated. `high`, `medium` and `low` are only supported for `gpt-image-1`. `dall-e-2` only supports `standard` quality. Defaults to `auto`. <br>  |
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
curl -s -D >(grep -i x-request-id >&2) \
  -o >(jq -r '.data[0].b64_json' | base64 --decode > gift-basket.png) \
  -X POST "https://api.openai.com/v1/images/edits" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -F "model=gpt-image-1" \
  -F "image[]=@body-lotion.png" \
  -F "image[]=@bath-bomb.png" \
  -F "image[]=@incense-kit.png" \
  -F "image[]=@soap.png" \
  -F 'prompt=Create a lovely gift basket with these four items in it'

```

#### python
```python
import base64
from openai import OpenAI
client = OpenAI()

prompt = """
Generate a photorealistic image of a gift basket on a white background 
labeled 'Relax & Unwind' with a ribbon and handwriting-like font, 
containing all the items in the reference pictures.
"""

result = client.images.edit(
    model="gpt-image-1",
    image=[
        open("body-lotion.png", "rb"),
        open("bath-bomb.png", "rb"),
        open("incense-kit.png", "rb"),
        open("soap.png", "rb"),
    ],
    prompt=prompt
)

image_base64 = result.data[0].b64_json
image_bytes = base64.b64decode(image_base64)

# Save the image to a file
with open("gift-basket.png", "wb") as f:
    f.write(image_bytes)

```

#### node.js
```javascript
import fs from "fs";
import OpenAI, { toFile } from "openai";

const client = new OpenAI();

const imageFiles = [
    "bath-bomb.png",
    "body-lotion.png",
    "incense-kit.png",
    "soap.png",
];

const images = await Promise.all(
    imageFiles.map(async (file) =>
        await toFile(fs.createReadStream(file), null, {
            type: "image/png",
        })
    ),
);

const rsp = await client.images.edit({
    model: "gpt-image-1",
    image: images,
    prompt: "Create a lovely gift basket with these four items in it",
});

// Save the image to a file
const image_base64 = rsp.data[0].b64_json;
const image_bytes = Buffer.from(image_base64, "base64");
fs.writeFileSync("basket.png", image_bytes);

```

### Response Example

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

