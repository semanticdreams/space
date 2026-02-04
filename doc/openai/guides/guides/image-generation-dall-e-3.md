Image generation
================

Learn how to generate or edit images.

Overview
--------

The OpenAI API lets you generate and edit images from text prompts, using the GPT Image or DALL·E models.

Currently, image generation is only available through the [Image API](/docs/api-reference/images). We’re actively working on expanding support to the [Responses API](/docs/api-reference/responses).

The [Image API](/docs/api-reference/images) provides three endpoints, each with distinct capabilities:

*   **Generations**: [Generate images](#generate-images) from scratch based on a text prompt
*   **Edits**: [Modify existing images](#edit-images) using a new prompt, either partially or entirely
*   **Variations**: [Generate variations](#image-variations) of an existing image (available with DALL·E 2 only)

You can also [customize the output](#customize-image-output) by specifying the quality, size, format, compression, and whether you would like a transparent background.

DALL·E 3 is our previous generation model and has some limitations. For a better experience, we recommend using [GPT Image](/docs/guides/image-generation?image-generation-model=gpt-image-1).

### Model comparison

Our latest and most advanced model for image generation is `gpt-image-1`, a natively multimodal language model.

We recommend this model for its high-quality image generation and ability to use world knowledge in image creation. However, you can also use specialized image generation models—DALL·E 2 and DALL·E 3—with the Image API.

|Model|Endpoints|Use case|
|---|---|---|
|DALL·E 2|Image API: Generations, Edits, Variations|Lower cost, concurrent requests, inpainting (image editing with a mask)|
|DALL·E 3|Image API: Generations only|Higher image quality than DALL·E 2, support for larger resolutions|
|GPT Image|Image API: Generations, Edits – Responses API support coming soon|Superior instruction following, text rendering, detailed editing, real-world knowledge|

This guide focuses on DALL·E 3, but you can also switch to the docs for [GPT Image](/docs/guides/image-generation?image-generation-model=gpt-image-1) and [DALL·E 2](/docs/guides/image-generation?image-generation-model=dall-e-2).

![a vet with a baby otter](https://cdn.openai.com/API/docs/images/otter.png)

Generate Images
---------------

You can use the [image generation endpoint](/docs/api-reference/images/create) to create images based on text prompts. To learn more about customizing the output (size, quality, format, transparency), refer to the [customize image output](#customize-image-output) section below.

Generate an image

```javascript
import OpenAI from "openai";
const openai = new OpenAI();

const result = await openai.images.generate({
  model: "dall-e-3",
  prompt: "a white siamese cat",
  size: "1024x1024",
});

console.log(result.data[0].url);
```

```python
from openai import OpenAI
client = OpenAI()

result = client.images.generate(
    model="dall-e-3",
    prompt="a white siamese cat",
    size="1024x1024"
)

print(result.data[0].url)
```

```bash
curl https://api.openai.com/v1/images/generations \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -d '{
    "model": "dall-e-3",
    "prompt": "a white siamese cat",
    "size": "1024x1024"
  }'
```

### Prompting tips

When you use DALL·E 3, OpenAI automatically rewrites your prompt for safety reasons and to add more detail.

You can't disable this feature, but you can get outputs closer to your requested image by adding the following to your prompt:

`I NEED to test how the tool works with extremely simple prompts. DO NOT add any detail, just use it AS-IS:`

The updated prompt is visible in the `revised_prompt` field of the data response object.

Edit Images
-----------

The Image Edits endpoint is not available for DALL·E 3. If you would like to edit images, we recommend using our newest model, [GPT Image](/docs/guides/image-generation?image-generation-model=gpt-image-1).

Customize Image Output
----------------------

You can configure the following output options:

*   **Size**: Image dimensions (e.g., `1024x1024`, `1024x1536`)
*   **Quality**: Rendering quality (e.g. `standard`)
*   **Format**: `url` (default), `b64_json`

### Size and quality options

Square images with standard quality are the fastest to generate. The default size is 1024x1024 pixels.

|Available sizes|1024x1024 (square)1024x1792 (portrait)1792x1024 (landscape)auto (default)|
|Quality options|standard (default)hd|

### Output format

The default Image API output when using DALL·E 3 is a url pointing to the hosted image. You can also request the `response_format` as `b64_json` for a base64-encoded image.

Limitations
-----------

DALL·E 3 is an improvement over DALL·E 2 but still has some limitations:

*   **Text Rendering:** The model struggles with rendering legible text.
*   **Instruction Following:** The model has trouble following precise instructions.
*   **Photorealism:** The model is not able to generate highly photorealistic images.

For a better experience, we recommend using [GPT Image](/docs/guides/image-generation?image-generation-model=gpt-image-1) for image generation.

Cost and latency
----------------

Cost for DALL·E 3 is fixed can be calculated by image generated depending on the size and image quality.

You can find the pricing details on the [pricing page](/pricing#image-generation).