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

### Model comparison

Our latest and most advanced model for image generation is `gpt-image-1`, a natively multimodal language model.

We recommend this model for its high-quality image generation and ability to use world knowledge in image creation. However, you can also use specialized image generation models—DALL·E 2 and DALL·E 3—with the Image API.

|Model|Endpoints|Use case|
|---|---|---|
|DALL·E 2|Image API: Generations, Edits, Variations|Lower cost, concurrent requests, inpainting (image editing with a mask)|
|DALL·E 3|Image API: Generations only|Higher image quality than DALL·E 2, support for larger resolutions|
|GPT Image|Image API: Generations, Edits – Responses API support coming soon|Superior instruction following, text rendering, detailed editing, real-world knowledge|

This guide focuses on GPT Image, but you can also switch to the docs for [DALL·E 2](/docs/guides/image-generation?image-generation-model=dall-e-2) and [DALL·E 3](/docs/guides/image-generation?image-generation-model=dall-e-3).

To ensure this model is used responsibly, you may need to complete the [API Organization Verification](https://help.openai.com/en/articles/10910291-api-organization-verification) from your [developer console](https://platform.openai.com/settings/organization/general) before using `gpt-image-1`.

![a vet with a baby otter](https://cdn.openai.com/API/docs/images/otter.png)

Generate Images
---------------

You can use the [image generation endpoint](/docs/api-reference/images/create) to create images based on text prompts. To learn more about customizing the output (size, quality, format, transparency), refer to the [customize image output](#customize-image-output) section below.

You can set the `n` parameter to generate multiple images at once in a single request (by default, the API returns a single image).

Generate an image

```javascript
import OpenAI from "openai";
import fs from "fs";
const openai = new OpenAI();

const prompt = `
A children's book drawing of a veterinarian using a stethoscope to 
listen to the heartbeat of a baby otter.
`;

const result = await openai.images.generate({
    model: "gpt-image-1",
    prompt,
});

// Save the image to a file
const image_base64 = result.data[0].b64_json;
const image_bytes = Buffer.from(image_base64, "base64");
fs.writeFileSync("otter.png", image_bytes);
```

```python
from openai import OpenAI
import base64
client = OpenAI()

prompt = """
A children's book drawing of a veterinarian using a stethoscope to 
listen to the heartbeat of a baby otter.
"""

result = client.images.generate(
    model="gpt-image-1",
    prompt=prompt
)

image_base64 = result.data[0].b64_json
image_bytes = base64.b64decode(image_base64)

# Save the image to a file
with open("otter.png", "wb") as f:
    f.write(image_bytes)
```

```bash
curl -X POST "https://api.openai.com/v1/images/generations" \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    -H "Content-type: application/json" \
    -d '{
        "model": "gpt-image-1",
        "prompt": "A childrens book drawing of a veterinarian using a stethoscope to listen to the heartbeat of a baby otter."
    }' | jq -r '.data[0].b64_json' | base64 --decode > otter.png
```

Edit Images
-----------

The [image edits](/docs/api-reference/images/createEdit) endpoint lets you:

*   Edit existing images
*   Generate new images using other images as a reference
*   Edit parts of an image by uploading an image and mask indicating which areas should be replaced (a process known as **inpainting**)

### Create a new image using image references

You can use one or more images as a reference to generate a new image.

In this example, we'll use 4 input images to generate a new image of a gift basket containing the items in the reference images.

[![Body Lotion](https://cdn.openai.com/API/docs/images/body-lotion.png)](https://cdn.openai.com/API/docs/images/body-lotion.png)[![Soap](https://cdn.openai.com/API/docs/images/soap.png)](https://cdn.openai.com/API/docs/images/soap.png)[![Incense Kit](https://cdn.openai.com/API/docs/images/incense-kit.png)](https://cdn.openai.com/API/docs/images/incense-kit.png)[![Bath Bomb](https://cdn.openai.com/API/docs/images/bath-bomb.png)](https://cdn.openai.com/API/docs/images/bath-bomb.png)

![Bath Gift Set](https://cdn.openai.com/API/docs/images/bath-set-result.png)

Edit an image

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
  -F 'prompt=Generate a photorealistic image of a gift basket on a white background labeled "Relax & Unwind" with a ribbon and handwriting-like font, containing all the items in the reference pictures'
```

### Edit an image using a mask (inpainting)

You can provide a mask to indicate where the image should be edited. The transparent areas of the mask will be replaced, while the filled areas will be left unchanged.

You can use the prompt to describe what you want the final edited image to be or what you want to edit specifically. If you provide multiple input images, the mask will be applied to the first image.

Edit an image

```python
from openai import OpenAI
client = OpenAI()

result = client.images.edit(
    model="gpt-image-1",
    image=open("sunlit_lounge.png", "rb"),
    mask=open("mask.png", "rb"),
    prompt="A sunlit indoor lounge area with a pool containing a flamingo"
)

image_base64 = result.data[0].b64_json
image_bytes = base64.b64decode(image_base64)

# Save the image to a file
with open("composition.png", "wb") as f:
    f.write(image_bytes)
```

```javascript
import fs from "fs";
import OpenAI, { toFile } from "openai";

const client = new OpenAI();

const rsp = await client.images.edit({
    model: "gpt-image-1",
    image: await toFile(fs.createReadStream("sunlit_lounge.png"), null, {
        type: "image/png",
    }),
    mask: await toFile(fs.createReadStream("mask.png"), null, {
        type: "image/png",
    }),
    prompt: "A sunlit indoor lounge area with a pool containing a flamingo",
});

// Save the image to a file
const image_base64 = rsp.data[0].b64_json;
const image_bytes = Buffer.from(image_base64, "base64");
fs.writeFileSync("lounge.png", image_bytes);
```

```bash
curl -s -D >(grep -i x-request-id >&2) \
  -o >(jq -r '.data[0].b64_json' | base64 --decode > lounge.png) \
  -X POST "https://api.openai.com/v1/images/edits" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -F "model=gpt-image-1" \
  -F "mask=@mask.png" \   
  -F "image[]=@sunlit_lounge.png" \
  -F 'prompt=A sunlit indoor lounge area with a pool containing a flamingo'
```

|Image|Mask|Output|
|---|---|---|
||||

Prompt: a sunlit indoor lounge area with a pool containing a flamingo

#### Mask requirements

The image to edit and mask must be of the same format and size (less than 25MB in size).

The mask image must also contain an alpha channel. If you're using an image editing tool to create the mask, make sure to save the mask with an alpha channel.

Add an alpha channel to a black and white mask

You can modify a black and white image programmatically to add an alpha channel.

Add an alpha channel to a black and white mask

```python
from PIL import Image
from io import BytesIO

# 1. Load your black & white mask as a grayscale image
mask = Image.open(img_path_mask).convert("L")

# 2. Convert it to RGBA so it has space for an alpha channel
mask_rgba = mask.convert("RGBA")

# 3. Then use the mask itself to fill that alpha channel
mask_rgba.putalpha(mask)

# 4. Convert the mask into bytes
buf = BytesIO()
mask_rgba.save(buf, format="PNG")
mask_bytes = buf.getvalue()

# 5. Save the resulting file
img_path_mask_alpha = "mask_alpha.png"
with open(img_path_mask_alpha, "wb") as f:
    f.write(mask_bytes)
```

Customize Image Output
----------------------

You can configure the following output options:

*   **Size**: Image dimensions (e.g., `1024x1024`, `1024x1536`)
*   **Quality**: Rendering quality (e.g. `low`, `medium`, `high`)
*   **Format**: File output format
*   **Compression**: Compression level (0-100%) for JPEG and WebP formats
*   **Background**: Transparent or opaque

`size`, `quality`, and `background` support the `auto` option, where the model will automatically select the best option based on the prompt.

### Size and quality options

Square images with standard quality are the fastest to generate. The default size is 1024x1024 pixels.

|Available sizes|1024x1024 (square)1536x1024 (landscape)1024x1536 (portrait)auto (default)|
|Quality options|lowmediumhighauto (default)|

### Output format

The Image API returns base64-encoded image data. The default format is `png`, but you can also request `jpeg` or `webp`.

If using `jpeg` or `webp`, you can also specify the `output_compression` parameter to control the compression level (0-100%). For example, `output_compression=50` will compress the image by 50%.

### Transparency

The `gpt-image-1` model supports transparent backgrounds. To enable transparency, set the `background` parameter to `transparent`.

It is only supported with the `png` and `webp` output formats.

Transparency works best when setting the quality to `medium` or `high`.

Generate an image with a transparent background

```javascript
import OpenAI from "openai";
import fs from "fs";
const openai = new OpenAI();

const result = await openai.images.generate({
    model: "gpt-image-1",
    prompt: "Draw a 2D pixel art style sprite sheet of a tabby gray cat",
    size: "1024x1024",
    background: "transparent",
    quality: "high",
});

// Save the image to a file
const image_base64 = result.data[0].b64_json;
const image_bytes = Buffer.from(image_base64, "base64");
fs.writeFileSync("sprite.png", image_bytes);
```

```python
from openai import OpenAI
import base64
client = OpenAI()

result = client.images.generate(
    model="gpt-image-1",
    prompt="Draw a 2D pixel art style sprite sheet of a tabby gray cat",
    size="1024x1024",
    background="transparent",
    quality="high",
)

image_base64 = result.json()["data"][0]["b64_json"]
image_bytes = base64.b64decode(image_base64)

# Save the image to a file
with open("sprite.png", "wb") as f:
    f.write(image_bytes)
```

```bash
curl -X POST "https://api.openai.com/v1/images" \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    -H "Content-type: application/json" \
    -d '{
        "prompt": "Draw a 2D pixel art style sprite sheet of a tabby gray cat",
        "quality": "high",
        "size": "1024x1024",
        "background": "transparent"
    }' | jq -r 'data[0].b64_json' | base64 --decode > sprite.png
```

Limitations
-----------

The GPT-4o Image model is a powerful and versatile image generation model, but it still has some limitations to be aware of:

*   **Latency:** Complex prompts may take up to 2 minutes to process.
*   **Text Rendering:** Although significantly improved over the DALL·E series, the model can still struggle with precise text placement and clarity.
*   **Consistency:** While capable of producing consistent imagery, the model may occasionally struggle to maintain visual consistency for recurring characters or brand elements across multiple generations.
*   **Composition Control:** Despite improved instruction following, the model may have difficulty placing elements precisely in structured or layout-sensitive compositions.

### Content Moderation

All prompts and generated images are filtered in accordance with our [content policy](https://labs.openai.com/policies/content-policy).

For image generation using `gpt-image-1`, you can control moderation strictness with the `moderation` parameter. This parameter supports two values:

*   `auto` (default): Standard filtering that seeks to limit creating certain categories of potentially age-inappropriate content.
*   `low`: Less restrictive filtering.

Cost and latency
----------------

This model generates images by first producing specialized image tokens. Both latency and eventual cost are proportional to the number of tokens required to render an image—larger image sizes and higher quality settings result in more tokens.

The number of tokens generated depends on image dimensions and quality:

|Quality|Square (1024×1024)|Portrait (1024×1536)|Landscape (1536×1024)|
|---|---|---|---|
|Low|272 tokens|408 tokens|400 tokens|
|Medium|1056 tokens|1584 tokens|1568 tokens|
|High|4160 tokens|6240 tokens|6208 tokens|

Note that you will also need to account for [input tokens](/docs/guides/images-vision#gpt-image-1): text tokens for the prompt and image tokens for the input images if editing images.

So the final cost is the sum of:

*   input text tokens
*   input image tokens if using the edits endpoint
*   image output tokens

Refer to our [pricing page](/pricing#image-generation) for more information about price per text and image tokens.